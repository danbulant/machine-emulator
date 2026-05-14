/* Puppet: a libcmt rollup target driven by its inputs.
 *
 * Each advance-state payload is a command of the form "verb:data" (or
 * a bare verb without a colon).  The verb selects the libcmt call; the
 * data after the colon is the bytes the call receives.
 *
 *   notice:<data>     -> cmt_rollup_emit_notice(data), accept
 *   report:<data>     -> cmt_rollup_emit_report(data), accept
 *   voucher:<data>    -> cmt_rollup_emit_voucher(msg_sender, 0, data),
 *                        accept
 *   exception:<data>  -> cmt_rollup_emit_exception(data); halts
 *   exit              -> break out of the loop and return from main;
 *                        the machine halts on its own
 *   <anything else>   -> reject the advance; the host rolls the state
 *                        back
 *
 * An inspect-state query is echoed back as a single report, accepted.
 */

#include <string.h>
#include "libcmt/rollup.h"

static int verb_match(const cmt_abi_bytes_t *payload, const char *verb, cmt_abi_bytes_t *data) {
    size_t verb_len = strlen(verb);
    if (payload->length < verb_len) return 0;
    if (memcmp(payload->data, verb, verb_len) != 0) return 0;
    if (payload->length == verb_len) {
        data->data = NULL;
        data->length = 0;
        return 1;
    }
    if (((const char *) payload->data)[verb_len] != ':') return 0;
    data->data = (char *) payload->data + verb_len + 1;
    data->length = payload->length - verb_len - 1;
    return 1;
}

int main(void) {
    cmt_rollup_t rollup;
    if (cmt_rollup_init(&rollup) < 0) return 1;

    cmt_rollup_finish_t finish = { .accept_previous_request = true };
    if (cmt_rollup_finish(&rollup, &finish) < 0) return 1;

    for (;;) {
        bool accept = true;
        bool should_exit = false;
        if (finish.next_request_type == HTIF_YIELD_REASON_ADVANCE) {
            cmt_rollup_advance_t advance;
            if (cmt_rollup_read_advance_state(&rollup, &advance) < 0) break;
            cmt_abi_bytes_t data;
            if (verb_match(&advance.payload, "notice", &data)) {
                cmt_rollup_emit_notice(&rollup, &data, NULL);
            } else if (verb_match(&advance.payload, "report", &data)) {
                cmt_rollup_emit_report(&rollup, &data);
            } else if (verb_match(&advance.payload, "voucher", &data)) {
                cmt_abi_u256_t value = {{0}};
                cmt_rollup_emit_voucher(&rollup, &advance.msg_sender, &value, &data, NULL);
            } else if (verb_match(&advance.payload, "exception", &data)) {
                cmt_rollup_emit_exception(&rollup, &data);
            } else if (verb_match(&advance.payload, "exit", &data) && data.length == 0) {
                should_exit = true;
            } else {
                accept = false;
            }
        } else if (finish.next_request_type == HTIF_YIELD_REASON_INSPECT) {
            cmt_rollup_inspect_t inspect;
            if (cmt_rollup_read_inspect_state(&rollup, &inspect) < 0) break;
            cmt_rollup_emit_report(&rollup, &inspect.payload);
        }
        if (should_exit) break;
        finish.accept_previous_request = accept;
        if (cmt_rollup_finish(&rollup, &finish) < 0) break;
    }

    cmt_rollup_fini(&rollup);
    return 0;
}
