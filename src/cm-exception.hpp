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

#ifndef CM_EXCEPTION_HPP
#define CM_EXCEPTION_HPP

#include <any>
#include <exception>
#include <functional>
#include <memory>
#include <new>
#include <optional>
#include <stdexcept>
#include <string>
#include <typeinfo>
#include <variant>

#include "cm.h"

namespace cartesi {

/// \brief Reconstructed exception for CM_ERROR_EXCEPTION (any std::exception subclass not otherwise mapped).
struct cm_reconstructed_exception : std::exception {
    explicit cm_reconstructed_exception(std::string msg) : m_what(std::move(msg)) {}
    const char *what() const noexcept override {
        return m_what.c_str();
    }

private:
    std::string m_what;
};

/// \brief Reconstructed exception for CM_ERROR_UNKNOWN (non-std::exception throw).
struct cm_reconstructed_unknown {};

/// \brief Returns the cm_error code for the exception currently being handled,
/// and writes its message into \p message.
/// \details Must be called from within an active exception handler. Two passes:
/// pass 1 extracts the message; pass 2 dispatches on dynamic type. Both use
/// the same re-throw trick -- the caller's exception remains "currently handled"
/// across both passes because the caller's catch clause is still on the stack.
inline cm_error cm_exception_to_error_code(std::string &message) noexcept {
    // Pass 1: extract message.
    try {
        throw;
    } catch (const std::exception &e) {
        try {
            message = e.what();
        } catch (...) {
            message.clear();
        }
    } catch (...) {
        try {
            message = "unknown error";
        } catch (...) {
            message.clear();
        }
    }
    // Pass 2: dispatch on type.
    try {
        throw;
    } catch (const std::invalid_argument &) {
        return CM_ERROR_INVALID_ARGUMENT;
    } catch (const std::domain_error &) {
        return CM_ERROR_DOMAIN_ERROR;
    } catch (const std::length_error &) {
        return CM_ERROR_LENGTH_ERROR;
    } catch (const std::out_of_range &) {
        return CM_ERROR_OUT_OF_RANGE;
    } catch (const std::logic_error &) {
        return CM_ERROR_LOGIC_ERROR;
    } catch (const std::bad_optional_access &) {
        return CM_ERROR_BAD_OPTIONAL_ACCESS;
    } catch (const std::range_error &) {
        return CM_ERROR_RANGE_ERROR;
    } catch (const std::overflow_error &) {
        return CM_ERROR_OVERFLOW_ERROR;
    } catch (const std::underflow_error &) {
        return CM_ERROR_UNDERFLOW_ERROR;
    } catch (const std::runtime_error &) {
        return CM_ERROR_RUNTIME_ERROR;
    } catch (const std::bad_typeid &) {
        return CM_ERROR_BAD_TYPEID;
    } catch (const std::bad_any_cast &) {
        return CM_ERROR_BAD_ANY_CAST;
    } catch (const std::bad_cast &) {
        return CM_ERROR_BAD_CAST;
    } catch (const std::bad_weak_ptr &) {
        return CM_ERROR_BAD_WEAK_PTR;
    } catch (const std::bad_function_call &) {
        return CM_ERROR_BAD_FUNCTION_CALL;
    } catch (const std::bad_array_new_length &) {
        return CM_ERROR_BAD_ARRAY_NEW_LENGTH;
    } catch (const std::bad_alloc &) {
        return CM_ERROR_BAD_ALLOC;
    } catch (const std::bad_exception &) {
        return CM_ERROR_BAD_EXCEPTION;
    } catch (const std::bad_variant_access &) {
        return CM_ERROR_BAD_VARIANT_ACCESS;
    } catch (const std::exception &) {
        return CM_ERROR_EXCEPTION;
    } catch (...) {
        return CM_ERROR_UNKNOWN;
    }
}

/// \brief Throws the exception corresponding to the given cm_error code.
/// \details Uses cm_reconstructed_exception/cm_reconstructed_unknown for codes
/// that cannot be faithfully reconstructed from a message string alone.
[[noreturn]] inline void cm_error_code_to_exception(cm_error code, const std::string &message) {
    switch (code) {
        case CM_ERROR_INVALID_ARGUMENT:
            throw std::invalid_argument(message);
        case CM_ERROR_DOMAIN_ERROR:
            throw std::domain_error(message);
        case CM_ERROR_LENGTH_ERROR:
            throw std::length_error(message);
        case CM_ERROR_OUT_OF_RANGE:
            throw std::out_of_range(message);
        case CM_ERROR_LOGIC_ERROR:
            throw std::logic_error(message);
        case CM_ERROR_RANGE_ERROR:
            throw std::range_error(message);
        case CM_ERROR_OVERFLOW_ERROR:
            throw std::overflow_error(message);
        case CM_ERROR_UNDERFLOW_ERROR:
            throw std::underflow_error(message);
        case CM_ERROR_BAD_OPTIONAL_ACCESS:
            throw std::bad_optional_access();
        case CM_ERROR_BAD_TYPEID:
            throw std::bad_typeid();
        case CM_ERROR_BAD_ANY_CAST:
            throw std::bad_any_cast();
        case CM_ERROR_BAD_CAST:
            throw std::bad_cast();
        case CM_ERROR_BAD_WEAK_PTR:
            throw std::bad_weak_ptr();
        case CM_ERROR_BAD_FUNCTION_CALL:
            throw std::bad_function_call();
        case CM_ERROR_BAD_ALLOC:
            throw std::bad_alloc();
        case CM_ERROR_BAD_ARRAY_NEW_LENGTH:
            throw std::bad_array_new_length();
        case CM_ERROR_BAD_EXCEPTION:
            throw std::bad_exception();
        case CM_ERROR_BAD_VARIANT_ACCESS:
            throw std::bad_variant_access();
        case CM_ERROR_OK:
            throw std::logic_error("cm_error_code_to_exception called with CM_ERROR_OK");
        case CM_ERROR_RUNTIME_ERROR:
            throw std::runtime_error(message);
        case CM_ERROR_EXCEPTION:
            throw cm_reconstructed_exception(message);
        case CM_ERROR_UNKNOWN:
        default:
            throw cm_reconstructed_unknown{}; // NOLINT(hicpp-exception-baseclass)
    }
}

} // namespace cartesi

#endif // CM_EXCEPTION_HPP
