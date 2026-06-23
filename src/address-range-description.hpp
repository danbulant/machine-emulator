// Copyright Cartesi and individual authors (see AUTHORS)
// SPDX-License-Identifier: LGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU Lesser General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option) any
// later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
// PARTICULAR PURPOSE. See the GNU Lesser General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public License along
// with this program (see COPYING). If not, see <https://www.gnu.org/licenses/>.
//

#ifndef ADDRESS_RANGE_DESCRIPTION_HPP
#define ADDRESS_RANGE_DESCRIPTION_HPP

#include <cstdint>
#include <string>
#include <vector>

namespace cartesi {

/// \brief Description of an address range used for introspection (i.e., get_address_ranges())
struct address_range_description {
    uint64_t start = 0;               ///< Start of memory range
    uint64_t length = 0;              ///< Length of memory range
    std::string description;          ///< User-friendly description for memory range
    bool is_memory = false;           ///< True if range is memory (false if device)
    bool is_device = false;           ///< True if range is a device
    bool is_readable = false;         ///< True if range is readable by the machine
    bool is_writeable = false;        ///< True if range is writeable by the machine
    bool is_executable = false;       ///< True if range is executable by the machine
    bool is_read_idempotent = false;  ///< True if reads from range are idempotent
    bool is_write_idempotent = false; ///< True if writes to range are idempotent
    uint64_t driver_id = 0;           ///< Driver identifier for range
};

/// \brief List of address range descriptions used for introspection (i.e., get_address_ranges())
using address_range_descriptions = std::vector<address_range_description>;

} // namespace cartesi

#endif
