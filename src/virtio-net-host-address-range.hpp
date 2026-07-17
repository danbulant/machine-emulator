// Copyright Cartesi and individual authors (see AUTHORS)
// SPDX-License-Identifier: LGPL-3.0-or-later

#ifndef VIRTIO_NET_HOST_ADDRESS_RANGE_HPP
#define VIRTIO_NET_HOST_ADDRESS_RANGE_HPP

#include <cstdint>
#include <deque>
#include <vector>

#include "i-device-state-access-fwd.hpp"
#include "virtio-address-range.hpp"

namespace cartesi {

/// \brief Host-backed VirtIO network device for embedders that provide Ethernet frames directly.
class virtio_net_host_address_range final : public virtio_address_range {
    std::deque<std::vector<uint8_t>> m_receive_packets;
    std::deque<std::vector<uint8_t>> m_transmit_packets;

public:
    explicit virtio_net_host_address_range(uint64_t start, uint64_t length, uint32_t virtio_idx);

    virtio_net_host_address_range(const virtio_net_host_address_range &other) = delete;
    virtio_net_host_address_range &operator=(const virtio_net_host_address_range &other) = delete;
    virtio_net_host_address_range &operator=(virtio_net_host_address_range &&other) = delete;

    virtio_net_host_address_range(virtio_net_host_address_range &&other) = default;
    ~virtio_net_host_address_range() override = default;

    bool push_receive_packet(i_device_state_access *a, const uint8_t *data, uint32_t length);
    bool take_transmit_packet(std::vector<uint8_t> *packet);
    void clear_packets();

private:
    void do_on_device_reset() override;
    void do_on_device_ok(i_device_state_access *a) override;
    bool do_on_device_queue_available(i_device_state_access *a, uint32_t queue_idx, uint16_t desc_idx,
        uint32_t read_avail_len, uint32_t write_avail_len, virtq_event &e) override;

    bool receive_one(i_device_state_access *a, uint16_t desc_idx, uint32_t write_avail_len);
    bool transmit_one(i_device_state_access *a, uint16_t desc_idx, uint32_t read_avail_len);
    void deliver_receive_packets(i_device_state_access *a);
};

} // namespace cartesi

#endif
