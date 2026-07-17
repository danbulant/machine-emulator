// Copyright Cartesi and individual authors (see AUTHORS)
// SPDX-License-Identifier: LGPL-3.0-or-later

#include "virtio-net-host-address-range.hpp"

#include <array>
#include <cstdint>
#include <cstring>
#include <utility>
#include <vector>

#include "i-device-state-access.hpp"
#include "virtio-address-range.hpp"

namespace cartesi {

namespace {

constexpr uint32_t VIRTIO_NET_RECEIVEQ = 0;
constexpr uint32_t VIRTIO_NET_TRANSMITQ = 1;
constexpr uint32_t VIRTIO_NET_F_MAC = UINT32_C(1) << 5;
constexpr uint32_t VIRTIO_NET_MAX_FRAME_LENGTH = 2048;
constexpr size_t VIRTIO_NET_MAX_QUEUED_PACKETS = 256;

struct virtio_net_header {
    uint8_t flags;
    uint8_t gso_type;
    uint16_t hdr_len;
    uint16_t gso_size;
    uint16_t csum_start;
    uint16_t csum_offset;
    uint16_t num_buffers;
};

struct virtio_net_config_space {
    std::array<uint8_t, 6> mac;
};

constexpr std::array<uint8_t, 6> GUEST_MAC{0x02, 0x00, 0x00, 0x00, 0x00, 0x02};

} // namespace

virtio_net_host_address_range::virtio_net_host_address_range(uint64_t start, uint64_t length, uint32_t virtio_idx) :
    virtio_address_range("VirtIO host network", start, length, virtio_idx, VIRTIO_DEVICE_NETWORK, VIRTIO_NET_F_MAC,
        sizeof(virtio_net_config_space)) {
    const virtio_net_config_space config{.mac = GUEST_MAC};
    static_assert(sizeof(config) <= sizeof(config_space));
    std::memcpy(config_space.data(), &config, sizeof(config));
}

void virtio_net_host_address_range::do_on_device_reset() {
    clear_packets();
}

void virtio_net_host_address_range::do_on_device_ok(i_device_state_access *a) {
    deliver_receive_packets(a);
}

bool virtio_net_host_address_range::do_on_device_queue_available(i_device_state_access *a, uint32_t queue_idx,
    uint16_t desc_idx, uint32_t read_avail_len, uint32_t write_avail_len, virtq_event & /*e*/) {
    if (queue_idx == VIRTIO_NET_RECEIVEQ) {
        return receive_one(a, desc_idx, write_avail_len);
    }
    if (queue_idx == VIRTIO_NET_TRANSMITQ) {
        return transmit_one(a, desc_idx, read_avail_len);
    }
    notify_device_needs_reset(a);
    return false;
}

bool virtio_net_host_address_range::receive_one(i_device_state_access *a, uint16_t desc_idx,
    uint32_t write_avail_len) {
    if (m_receive_packets.empty()) {
        return false;
    }

    const auto &packet = m_receive_packets.front();
    const uint32_t written_len = static_cast<uint32_t>(sizeof(virtio_net_header) + packet.size());
    if (packet.size() > VIRTIO_NET_MAX_FRAME_LENGTH || write_avail_len < written_len) {
        notify_device_needs_reset(a);
        return false;
    }

    virtio_net_header header{};
    header.num_buffers = 1;
    auto &vq = queue[VIRTIO_NET_RECEIVEQ];
    if (!vq.write_desc_mem(a, desc_idx, 0, reinterpret_cast<const uint8_t *>(&header), sizeof(header)) ||
        !vq.write_desc_mem(a, desc_idx, sizeof(header), packet.data(), static_cast<uint32_t>(packet.size())) ||
        !consume_queue(a, VIRTIO_NET_RECEIVEQ, desc_idx, written_len)) {
        notify_device_needs_reset(a);
        return false;
    }

    m_receive_packets.pop_front();
    notify_queue_used(a);
    return true;
}

bool virtio_net_host_address_range::transmit_one(i_device_state_access *a, uint16_t desc_idx,
    uint32_t read_avail_len) {
    if (read_avail_len < sizeof(virtio_net_header) ||
        read_avail_len - sizeof(virtio_net_header) > VIRTIO_NET_MAX_FRAME_LENGTH) {
        notify_device_needs_reset(a);
        return false;
    }

    const uint32_t packet_len = read_avail_len - sizeof(virtio_net_header);
    std::vector<uint8_t> packet(packet_len);
    auto &vq = queue[VIRTIO_NET_TRANSMITQ];
    if ((packet_len > 0 && !vq.read_desc_mem(a, desc_idx, sizeof(virtio_net_header), packet.data(), packet_len)) ||
        !consume_queue(a, VIRTIO_NET_TRANSMITQ, desc_idx)) {
        notify_device_needs_reset(a);
        return false;
    }

    if (m_transmit_packets.size() < VIRTIO_NET_MAX_QUEUED_PACKETS) {
        m_transmit_packets.push_back(std::move(packet));
    }
    notify_queue_used(a);
    return true;
}

bool virtio_net_host_address_range::push_receive_packet(i_device_state_access *a, const uint8_t *data,
    uint32_t length) {
    if (data == nullptr || length == 0 || length > VIRTIO_NET_MAX_FRAME_LENGTH) {
        return false;
    }
    if (m_receive_packets.size() == VIRTIO_NET_MAX_QUEUED_PACKETS) {
        m_receive_packets.pop_front();
    }
    m_receive_packets.emplace_back(data, data + length);
    deliver_receive_packets(a);
    return true;
}

void virtio_net_host_address_range::deliver_receive_packets(i_device_state_access *a) {
    if (!driver_ok || m_receive_packets.empty()) {
        return;
    }
    virtq_event event;
    on_device_queue_notify(a, VIRTIO_NET_RECEIVEQ, event);
}

bool virtio_net_host_address_range::take_transmit_packet(std::vector<uint8_t> *packet) {
    if (packet == nullptr || m_transmit_packets.empty()) {
        return false;
    }
    *packet = std::move(m_transmit_packets.front());
    m_transmit_packets.pop_front();
    return true;
}

void virtio_net_host_address_range::clear_packets() {
    m_receive_packets.clear();
    m_transmit_packets.clear();
}

} // namespace cartesi
