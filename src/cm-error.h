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

#ifndef CM_ERROR_H // NOLINTBEGIN
#define CM_ERROR_H

/// \brief Error codes returned from the C API.
typedef enum cm_error {
    CM_ERROR_OK = 0,
    CM_ERROR_INVALID_ARGUMENT = -1,
    CM_ERROR_DOMAIN_ERROR = -2,
    CM_ERROR_LENGTH_ERROR = -3,
    CM_ERROR_OUT_OF_RANGE = -4,
    CM_ERROR_LOGIC_ERROR = -5,
    CM_ERROR_RUNTIME_ERROR = -6,
    CM_ERROR_RANGE_ERROR = -7,
    CM_ERROR_OVERFLOW_ERROR = -8,
    CM_ERROR_UNDERFLOW_ERROR = -9,
    CM_ERROR_REGEX_ERROR = -10,
    CM_ERROR_BAD_TYPEID = -11,
    CM_ERROR_BAD_CAST = -12,
    CM_ERROR_BAD_ANY_CAST = -13,
    CM_ERROR_BAD_OPTIONAL_ACCESS = -14,
    CM_ERROR_BAD_WEAK_PTR = -15,
    CM_ERROR_BAD_FUNCTION_CALL = -16,
    CM_ERROR_BAD_ALLOC = -17,
    CM_ERROR_BAD_ARRAY_NEW_LENGTH = -18,
    CM_ERROR_BAD_EXCEPTION = -19,
    CM_ERROR_BAD_VARIANT_ACCESS = -20,
    CM_ERROR_EXCEPTION = -21,
    CM_ERROR_UNKNOWN = -22,
} cm_error;

#endif // NOLINTEND
