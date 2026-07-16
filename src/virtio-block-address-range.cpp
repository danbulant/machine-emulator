// Copyright Cartesi and individual authors (see AUTHORS)
// SPDX-License-Identifier: LGPL-3.0-or-later

#include "virtio-block-address-range.hpp"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <vector>

#include "i-device-state-access.hpp"
#include "virtio-address-range.hpp"

namespace cartesi {

namespace {

constexpr uint32_t VIRTIO_BLOCK_QUEUE = 0;
constexpr uint32_t VIRTIO_BLOCK_HEADER_SIZE = 16;
constexpr uint32_t VIRTIO_BLOCK_STATUS_SIZE = 1;
constexpr uint32_t VIRTIO_BLOCK_SECTOR_SIZE = 512;

struct virtio_block_request_header {
    uint32_t type;
    uint32_t reserved;
    uint64_t sector;
};

} // namespace

virtio_block_address_range::virtio_block_address_range(uint64_t start, uint64_t length, uint32_t virtio_idx,
    uint64_t capacity) :
    virtio_address_range("VirtIO block", start, length, virtio_idx, VIRTIO_DEVICE_BLOCK, VIRTIO_BLK_F_FLUSH,
        sizeof(virtio_block_config_space)) {
    m_request_id_base = static_cast<uint64_t>(virtio_idx) << 32;
    m_next_request_id = m_request_id_base + 1;
    get_config()->capacity = capacity;
}

void virtio_block_address_range::do_on_device_reset() {
    m_host_requests.clear();
    m_pending_requests.clear();
    m_next_request_id = m_request_id_base + 1;
}

void virtio_block_address_range::do_on_device_ok(i_device_state_access * /*a*/) {
    // Nothing to do.
}

bool virtio_block_address_range::do_on_device_queue_available(i_device_state_access *a, uint32_t queue_idx,
    uint16_t desc_idx, uint32_t read_avail_len, uint32_t write_avail_len, virtq_event & /*e*/) {
    if (queue_idx != VIRTIO_BLOCK_QUEUE || read_avail_len < VIRTIO_BLOCK_HEADER_SIZE ||
        write_avail_len < VIRTIO_BLOCK_STATUS_SIZE) {
        notify_device_needs_reset(a);
        return false;
    }

    // last_used_idx remains on the in-flight descriptor until the host completes it. The guest may notify the queue
    // again in the meantime; do not export that same descriptor as a second request.
    if (!m_pending_requests.empty()) {
        return false;
    }

    virtq &vq = queue[queue_idx];
    virtio_block_request_header header{};
    // NOLINTNEXTLINE(cppcoreguidelines-pro-type-reinterpret-cast)
    if (!vq.read_desc_mem(a, desc_idx, 0, reinterpret_cast<uint8_t *>(&header), sizeof(header))) {
        notify_device_needs_reset(a);
        return false;
    }

    const uint32_t data_len = (header.type == VIRTIO_BLK_T_IN) ? (write_avail_len - VIRTIO_BLOCK_STATUS_SIZE) :
                                                            (read_avail_len - VIRTIO_BLOCK_HEADER_SIZE);
    const uint64_t end_sector = header.sector + ((static_cast<uint64_t>(data_len) + VIRTIO_BLOCK_SECTOR_SIZE - 1) /
                                                    VIRTIO_BLOCK_SECTOR_SIZE);
    if (end_sector > get_config()->capacity) {
        static constexpr uint8_t status = VIRTIO_BLK_S_IOERR;
        if (!vq.write_desc_mem(a, desc_idx, write_avail_len - VIRTIO_BLOCK_STATUS_SIZE, &status, sizeof(status)) ||
            !consume_queue(a, queue_idx, desc_idx, VIRTIO_BLOCK_STATUS_SIZE)) {
            notify_device_needs_reset(a);
            return false;
        }
        notify_queue_used(a);
        return true;
    }

    virtio_block_host_request request{};
    request.id = m_next_request_id++;
    request.type = header.type;
    request.sector = header.sector;
    request.length = data_len;

    switch (header.type) {
        case VIRTIO_BLK_T_OUT:
            request.data.resize(data_len);
            if (data_len > 0 && !vq.read_desc_mem(a, desc_idx, VIRTIO_BLOCK_HEADER_SIZE, request.data.data(), data_len)) {
                notify_device_needs_reset(a);
                return false;
            }
            break;
        case VIRTIO_BLK_T_IN:
        case VIRTIO_BLK_T_FLUSH:
            break;
        default: {
            static constexpr uint8_t status = VIRTIO_BLK_S_UNSUPP;
            if (!vq.write_desc_mem(a, desc_idx, write_avail_len - VIRTIO_BLOCK_STATUS_SIZE, &status, sizeof(status)) ||
                !consume_queue(a, queue_idx, desc_idx, VIRTIO_BLOCK_STATUS_SIZE)) {
                notify_device_needs_reset(a);
                return false;
            }
            notify_queue_used(a);
            return true;
        }
    }

    const uint32_t status_offset = (header.type == VIRTIO_BLK_T_IN) ? data_len : 0;
    m_pending_requests.push_back(pending_request{.id = request.id,
        .desc_idx = desc_idx,
        .type = header.type,
        .sector = header.sector,
        .data_len = data_len,
        .status_offset = status_offset});
    m_host_requests.push_back(std::move(request));

    // Stop consuming this queue until the host completes this async request. This keeps last_used_idx on the pending
    // descriptor so completions preserve the VirtIO split-ring order expected by the base implementation.
    return false;
}

bool virtio_block_address_range::take_host_request(virtio_block_host_request *request) {
    if (request == nullptr || m_host_requests.empty()) {
        return false;
    }
    *request = std::move(m_host_requests.front());
    m_host_requests.pop_front();
    return true;
}

bool virtio_block_address_range::complete_read(i_device_state_access *a, uint64_t id, const uint8_t *data,
    uint32_t length) {
    return complete(a, id, data, length, VIRTIO_BLK_S_OK);
}

bool virtio_block_address_range::complete_operation(i_device_state_access *a, uint64_t id) {
    return complete(a, id, nullptr, 0, VIRTIO_BLK_S_OK);
}

bool virtio_block_address_range::fail_operation(i_device_state_access *a, uint64_t id) {
    return complete(a, id, nullptr, 0, VIRTIO_BLK_S_IOERR);
}

bool virtio_block_address_range::complete(i_device_state_access *a, uint64_t id, const uint8_t *data, uint32_t length,
    uint8_t status) {
    if (m_pending_requests.empty() || m_pending_requests.front().id != id) {
        return false;
    }

    const pending_request request = m_pending_requests.front();
    virtq &vq = queue[VIRTIO_BLOCK_QUEUE];

    uint32_t written_len = VIRTIO_BLOCK_STATUS_SIZE;
    if (status == VIRTIO_BLK_S_OK && request.type == VIRTIO_BLK_T_IN) {
        if (data == nullptr || length != request.data_len) {
            return false;
        }
        if (length > 0 && !vq.write_desc_mem(a, request.desc_idx, 0, data, length)) {
            notify_device_needs_reset(a);
            return false;
        }
        written_len += length;
    }

    if (!vq.write_desc_mem(a, request.desc_idx, request.status_offset, &status, sizeof(status)) ||
        !consume_queue(a, VIRTIO_BLOCK_QUEUE, request.desc_idx, written_len)) {
        notify_device_needs_reset(a);
        return false;
    }

    m_pending_requests.pop_front();

    // If the driver had already submitted more descriptors before this async completion, queue the next one now.
    virtq_event e;
    on_device_queue_notify(a, VIRTIO_BLOCK_QUEUE, e);

    notify_queue_used(a);
    return true;
}

} // namespace cartesi
