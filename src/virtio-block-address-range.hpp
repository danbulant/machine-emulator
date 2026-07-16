// Copyright Cartesi and individual authors (see AUTHORS)
// SPDX-License-Identifier: LGPL-3.0-or-later

#ifndef VIRTIO_BLOCK_ADDRESS_RANGE_HPP
#define VIRTIO_BLOCK_ADDRESS_RANGE_HPP

#include <cstdint>
#include <deque>
#include <utility>
#include <vector>

#include "i-device-state-access-fwd.hpp"
#include "virtio-address-range.hpp"

namespace cartesi {

/// \brief VirtIO block features
enum virtio_block_features : uint64_t {
    VIRTIO_BLK_F_FLUSH = (UINT64_C(1) << 9), ///< Cache flush command support.
};

/// \brief VirtIO block request types
enum virtio_block_request_type : uint32_t {
    VIRTIO_BLK_T_IN = 0,     ///< Read sectors from device.
    VIRTIO_BLK_T_OUT = 1,    ///< Write sectors to device.
    VIRTIO_BLK_T_FLUSH = 4,  ///< Flush pending writes.
};

/// \brief VirtIO block status bytes
enum virtio_block_status : uint8_t {
    VIRTIO_BLK_S_OK = 0,
    VIRTIO_BLK_S_IOERR = 1,
    VIRTIO_BLK_S_UNSUPP = 2,
};

/// \brief VirtIO block config space
struct virtio_block_config_space {
    uint64_t capacity; // Capacity in 512-byte sectors.
};

/// \brief Request exported to the embedding host.
struct virtio_block_host_request {
    uint64_t id{};
    uint32_t type{};
    uint64_t sector{};
    uint32_t length{};
    std::vector<uint8_t> data{};
};

/// \brief Minimal async VirtIO block device.
class virtio_block_address_range final : public virtio_address_range {
    struct pending_request {
        uint64_t id{};
        uint16_t desc_idx{};
        uint32_t type{};
        uint64_t sector{};
        uint32_t data_len{};
        uint32_t status_offset{};
    };

    uint64_t m_request_id_base{0};
    uint64_t m_next_request_id{1};
    std::deque<virtio_block_host_request> m_host_requests;
    std::deque<pending_request> m_pending_requests;

public:
    explicit virtio_block_address_range(uint64_t start, uint64_t length, uint32_t virtio_idx, uint64_t capacity);

    virtio_block_address_range(const virtio_block_address_range &other) = delete;
    virtio_block_address_range &operator=(const virtio_block_address_range &other) = delete;
    virtio_block_address_range &operator=(virtio_block_address_range &&other) = delete;

    virtio_block_address_range(virtio_block_address_range &&other) = default;
    ~virtio_block_address_range() override = default;

    bool take_host_request(virtio_block_host_request *request);
    bool complete_read(i_device_state_access *a, uint64_t id, const uint8_t *data, uint32_t length);
    bool complete_operation(i_device_state_access *a, uint64_t id);
    bool fail_operation(i_device_state_access *a, uint64_t id);

    virtio_block_config_space *get_config() {
        // NOLINTNEXTLINE(cppcoreguidelines-pro-type-reinterpret-cast)
        return reinterpret_cast<virtio_block_config_space *>(config_space.data());
    }

private:
    void do_on_device_reset() override;
    void do_on_device_ok(i_device_state_access *a) override;
    bool do_on_device_queue_available(i_device_state_access *a, uint32_t queue_idx, uint16_t desc_idx,
        uint32_t read_avail_len, uint32_t write_avail_len, virtq_event &e) override;

    bool complete(i_device_state_access *a, uint64_t id, const uint8_t *data, uint32_t length, uint8_t status);
};

} // namespace cartesi

#endif
