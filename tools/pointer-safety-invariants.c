#define _POSIX_C_SOURCE 200809L

/*
 * Deterministic source and maths checks for pointer-output safety.
 *
 * Wine is carried here as a patch stack rather than directly linkable source.
 * Read context and added hunk lines from the original patches, then treat 0092
 * as the final override. Removed lines and commit prose cannot satisfy a check.
 */

#include <ctype.h>
#include <errno.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>

#define WHEEL_DELTA_VALUE 120
#define MAX_FRAME_MS_VALUE 16
#define MAX_PACKET_VALUE (WHEEL_DELTA_VALUE / 8)
#define MAX_TRAVEL_VALUE WHEEL_DELTA_VALUE
#define MAX_MESSAGES_VALUE 16
#define MAX_SPEED_VALUE 1200.0
#define MAX_TOTAL_VALUE \
    ((MAX_MESSAGES_VALUE * MAX_PACKET_VALUE < 2 * MAX_TRAVEL_VALUE) ? \
     MAX_MESSAGES_VALUE * MAX_PACKET_VALUE : 2 * MAX_TRAVEL_VALUE)

struct text
{
    char *data;
    size_t length;
    size_t capacity;
};

static unsigned int failures;

static void fail(const char *name, const char *detail)
{
    fprintf(stderr, "FAIL: %s: %s\n", name, detail);
    failures++;
}

static void pass(const char *name)
{
    printf("PASS: %s\n", name);
}

static int append(struct text *text, const char *data, size_t length)
{
    size_t needed = text->length + length + 1;
    char *resized;

    if (needed > text->capacity)
    {
        size_t capacity = text->capacity ? text->capacity : 4096;

        while (capacity < needed) capacity *= 2;
        if (!(resized = realloc(text->data, capacity))) return 0;
        text->data = resized;
        text->capacity = capacity;
    }
    memcpy(text->data + text->length, data, length);
    text->length += length;
    text->data[text->length] = 0;
    return 1;
}

/* Append the source represented by context and added hunk lines. */
static int read_patch_new_side(const char *path, struct text *result)
{
    FILE *file;
    char *line = NULL;
    size_t capacity = 0;
    ssize_t length;
    int in_hunk = 0, ok = 1;

    if (!(file = fopen(path, "r")))
    {
        fprintf(stderr, "FAIL: cannot open %s: %s\n", path, strerror(errno));
        return 0;
    }
    while ((length = getline(&line, &capacity, file)) >= 0)
    {
        if (!strncmp(line, "diff --git ", 11))
        {
            in_hunk = 0;
            continue;
        }
        if (!strncmp(line, "@@ ", 3) || !strncmp(line, "@@-", 3))
        {
            in_hunk = 1;
            continue;
        }
        if (!in_hunk || !length || line[0] == '-' || line[0] == '\\') continue;
        if ((line[0] == '+' && strncmp(line, "+++ ", 4)) || line[0] == ' ')
        {
            if (!append(result, line + 1, (size_t)length - 1))
            {
                ok = 0;
                break;
            }
        }
    }
    free(line);
    fclose(file);
    if (!ok) fprintf(stderr, "FAIL: out of memory while reading %s\n", path);
    return ok;
}

static char *compact(const char *source)
{
    size_t i, output = 0, length = strlen(source);
    char *result = malloc(length + 1);

    if (!result) return NULL;
    for (i = 0; i < length; i++)
        if (!isspace((unsigned char)source[i])) result[output++] = source[i];
    result[output] = 0;
    return result;
}

static size_t count_occurrences(const char *text, const char *needle)
{
    size_t count = 0, length = strlen(needle);

    while ((text = strstr(text, needle)))
    {
        count++;
        text += length;
    }
    return count;
}

static int require_text(const char *test, const char *text, const char *needle)
{
    if (!strstr(text, needle))
    {
        fail(test, needle);
        return 0;
    }
    return 1;
}

static int forbid_text(const char *test, const char *text, const char *needle)
{
    if (strstr(text, needle))
    {
        fail(test, needle);
        return 0;
    }
    return 1;
}

static int text_between_has(const char *text, const char *begin, const char *end,
                            const char *needle)
{
    const char *first = strstr(text, begin), *last;

    if (!first || !(last = strstr(first, end))) return -1;
    first = strstr(first, needle);
    return first && first < last;
}

static int require_text_between(const char *test, const char *text, const char *begin,
                                const char *end, const char *needle)
{
    int found = text_between_has(text, begin, end, needle);

    if (found == 1) return 1;
    fail(test, found < 0 ? "expected code section was not found" : needle);
    return 0;
}

static int forbid_text_between(const char *test, const char *text, const char *begin,
                               const char *end, const char *needle)
{
    int found = text_between_has(text, begin, end, needle);

    if (found == 0) return 1;
    fail(test, found < 0 ? "expected code section was not found" : needle);
    return 0;
}

static void check_pointer_setting_fallback(const char *stack, const char *override)
{
    int ok = 1;

    ok &= require_text("pointer settings use safe source fallback", override,
                       "staticconstchar*constsources[]={\"environment\",\"AppDefaultsregistry\","
                       "\"globalregistry\"};");
    ok &= require_text("application and global settings are read separately", override,
                       "key=source_index==1?appkey:defkey;");
    if (count_occurrences(override, "for(source_index=0;source_index<3;source_index++)") != 2)
    {
        fail("pointer settings try every available source",
             "expected one loop for named settings and one for InertiaRate");
        ok = 0;
    }
    if (count_occurrences(stack, "pointer_option_enum(defkey,appkey,") < 5)
    {
        fail("all named pointer settings use fallback", "one or more named settings bypass fallback");
        ok = 0;
    }
    ok &= require_text("invalid named settings fall through", override,
                       "WARN(\"unrecognized%svalue%sfromthe%s,ignoringit\\n\","
                       "name,debugstr_a(buffer),source);");
    ok &= require_text("invalid inertia rates fall through", override,
                       "WARN(\"InertiaRatevalue%sfromthe%sisnotadecimalin[0.5,16.0],ignoringit\\n\","
                       "debugstr_a(buffer),source);continue;");
    ok &= require_text("a valid inertia rate ends the search", override,
                       "pointer_config.inertia_rate=parsed;"
                       "TRACE(\"InertiaRate=%.2f(%s)\\n\",parsed,source);break;");
    ok &= require_text("disabled remains a valid inertia setting", stack,
                       "staticconstchar*constinertia_names[]={\"disabled\",\"auto\",\"enabled\"};");
    if (ok) pass("invalid settings cannot hide a lower-priority safety setting");
}

static void check_held_and_direct_input(const char *stack, const char *override)
{
    int ok = 1;

    ok &= require_text("held valuators advance the baseline and emit zero", stack,
                       "if(!axis->value_valid||reseed){axis->value=value;axis->value_valid=TRUE;return0;");
    ok &= require_text("all XI button state controls reseeding", stack,
                       "buttons_down=xinput2_any_button_down(event);");
    ok &= require_text("horizontal held movement is reseeded", stack,
                       "smooth_scroll_delta(&src->scroll_x,value_x,buttons_down,quantize,&discontinuity);");
    ok &= require_text("vertical held movement is reseeded", stack,
                       "smooth_scroll_delta(&src->scroll_y,value_y,buttons_down,quantize,&discontinuity);");
    ok &= require_text("button state cannot select an output mode", stack,
                       "quantize=pointer_config.smooth_scrolling==POINTER_SCROLL_NOTCHED;");
    ok &= forbid_text("held movement cannot become notched output", override,
                      "POINTER_SCROLL_NOTCHED||buttons_down");
    ok &= require_text("core wheel buttons are held-safe and fixed", override,
                       "if(pinch_button_is_wheel(event->button)){if(!pointer_button_down()&&"
                       "!x11drv_thread_data()->middle_drag.active)send_wheel_at_input(hwnd,pt,flags,"
                       "button_down_data[button],time,NULL,FALSE);");
    ok &= require_text("native XI wheel buttons are held-safe", override,
                       "if(pointer_button_down()||data->middle_drag.active){"
                       "pinch_button_release(event->detail);returnTRUE;}");
    ok &= require_text("native XI wheel buttons use fixed report positioning", override,
                       "send_xinput2_wheel_input(hwnd,pt,button_down_flags[button],"
                       "(int)button_down_data[button],time);");
    ok &= require_text("direct XI scroll separates cursor and wheel submission", override,
                       "if(!send_mouse_input(hwnd,pt,MOUSEEVENTF_ABSOLUTE,0,time,NULL))returnFALSE;"
                       "returnsend_wheel_at_input(hwnd,pt,flags,delta,time,NULL,FALSE);");
    ok &= forbid_text_between("cursor movement cannot inherit fixed-wheel flags", override,
                              "staticBOOLsend_xinput2_wheel_input(", "/*Addboundedinertia",
                              "MOUSEEVENTF_ABSOLUTE|flags");
    if (ok) pass("held-button and direct wheel paths cannot jump a dragged control");
}

static void check_direct_packet_bounds(const char *stack, const char *override)
{
    int ok = 1;

    if (count_occurrences(override, "staticconstintmax_delta=WHEEL_DELTA;") != 2)
    {
        fail("smooth and pinch reports are each limited to one notch",
             "expected one exact limit in each final decoder");
        ok = 0;
    }
    ok &= require_text("large smooth jumps reset their baseline", override,
                       "if(fabs(units)>2.0*max_delta){axis->value=value;"
                       "if(discontinuity)*discontinuity=TRUE;return0;}");
    ok &= require_text("smooth excess is discarded after one notch", stack,
                       "if((delta=round(units))>max_delta||delta<-max_delta){axis->value=value;"
                       "returndelta>0?max_delta:-max_delta;}");
    ok &= require_text("middle-drag vertical movement is bounded before sampling", stack,
                       "delta_y=middle_drag_delta(&drag->accum_y,notched);");
    ok &= require_text("middle-drag horizontal movement is bounded before sampling", stack,
                       "delta_x=middle_drag_delta(&drag->accum_x,notched);");
    ok &= require_text_between("pinch reports are limited to one notch", stack,
                               "staticBOOLX11DRV_GesturePinchEvent(",
                               "pthread_mutex_lock(&pinch_mutex);",
                               "staticconstintmax_delta=WHEEL_DELTA;");
    ok &= require_text("pinch cancellation is limited to one notch", stack,
                       "if(delta>max_delta)delta=max_delta;elseif(delta<-max_delta)delta=-max_delta;");
    ok &= require_text("live pinch updates are limited to one notch", stack,
                       "if((delta=round(units))>max_delta)delta=max_delta;"
                       "elseif(delta<-max_delta)delta=-max_delta;");
    ok &= require_text("pinch output stays at its begin point", stack,
                       "send_wheel_control_input(hwnd,anchor,delta,time);");
    ok &= require_text("unknown mouse buttons also block pinch output", override,
                       "returnpinch_state.buttons_down||pinch_state.other_buttons_down||"
                       "pinch_state.wheel_requests;");
    ok &= require_text("unknown button counts cannot wrap", override,
                       "elseif(pinch_state.other_buttons_down!=~0u)pinch_state.other_buttons_down++;");
    if (ok) pass("direct scroll, middle drag, and pinch packets are bounded");
}

static void check_delivered_samples_and_stops(const char *stack, const char *override)
{
    int ok = 1, deadline_evaluates;

    ok &= require_text("middle-drag speed uses bounded delivered units", stack,
                       "pointer_inertia_sample(x11drv_thread_data(),INERTIA_SOURCE_MIDDLE_DRAG,"
                       "drag->hwnd,drag->origin,delta_x,-delta_y,time);");
    ok &= require_text("smooth-scroll speed uses bounded delivered units", stack,
                       "pointer_inertia_sample(data,event->sourceid,hwnd,pt,delta_x,-delta_y,time);");
    ok &= forbid_text("smooth-scroll speed cannot use raw valuator units", override,
                      "pointer_inertia_sample(data,event->sourceid,hwnd,pt,units_");
    ok &= forbid_text("middle-drag speed cannot use raw pixel movement", override,
                      "drag->origin,move_x,-move_y,time)");
    ok &= require_text("unchanged scroll input is the explicit stop marker", stack,
                       "stop_marker=(have_x||have_y)&&");
    ok &= require_text("only a positive stop marker evaluates smooth coasting", override,
                       "if(stop_marker)pointer_inertia_stop_marker(data,event->sourceid,hwnd,time);"
                       "elseif(delta_x||delta_y)pointer_inertia_sample(");
    ok &= require_text("zero delivered movement cancels old history", override,
                       "elseif(delta_x||delta_y)pointer_inertia_sample(data,event->sourceid,hwnd,pt,"
                       "delta_x,-delta_y,time);elsepointer_inertia_cancel();");
    ok &= require_text_between("a discontinuity cancels prior history", override,
                               "if(buttons_down||discontinuity){",
                               "elseif(pointer_config.smooth_scrolling==POINTER_SCROLL_PRECISE)",
                               "pointer_inertia_cancel();");
    ok &= require_text_between("a discontinuity zeros both output axes", override,
                               "if(buttons_down||discontinuity){",
                               "elseif(pointer_config.smooth_scrolling==POINTER_SCROLL_PRECISE)",
                               "if(discontinuity)delta_x=delta_y=0;");
    deadline_evaluates = text_between_has(stack, "caseINERTIA_TRACKING:",
                                           "caseINERTIA_COASTING:", "pointer_inertia_evaluate(");
    if (deadline_evaluates != 0)
    {
        fail("silence alone cannot start coasting",
             deadline_evaluates < 0 ? "tracking block not found" : "tracking timeout evaluates history");
        ok = 0;
    }
    if (ok) pass("coasting uses delivered movement and requires a positive stop marker");
}

static void check_accumulator_routing(const char *override)
{
    int ok = 1;

    ok &= require_text("accumulated motion has an explicit pending state", override,
                       "BOOLmouse_motion_pending;");
    ok &= require_text("accumulated motion remembers its routing flags", override,
                       "UINTmouse_motion_flags;");
    ok &= require_text("empty pending state is checked explicitly", override,
                       "if(!info->mouse_motion_pending)returnSTATUS_SUCCESS;");
    ok &= require_text("pending motion is flushed with its own flags", override,
                       "if(info->mouse_motion_pending&&flags!=info->mouse_motion_flags){"
                       "NTSTATUSstatus=send_mouse_motion(info->mouse_motion_flags);if(status)returnstatus;}");
    ok &= require_text("new pending motion stores its flags", override,
                       "info->mouse_motion_flags=flags;info->mouse_motion_pending=TRUE;");
    ok &= require_text("submitted motion clears its pending state", override,
                       "info->mouse_motion_flags=0;info->mouse_motion_pending=FALSE;");
    if (ok) pass("queued cursor movement keeps its own routing flags");
}

static void check_inertia_limits(const char *stack, const char *override)
{
    int ok = 1;

    ok &= require_text("coast integration is limited to 16 ms", override,
                       "#defineINERTIA_MAX_FRAME_MS16");
    ok &= require_text("one coast packet is limited to 15 units", override,
                       "#defineINERTIA_MAX_PACKET(WHEEL_DELTA/8)");
    ok &= require_text("each coast axis is limited to 120 units", override,
                       "#defineINERTIA_MAX_TRAVELWHEEL_DELTA");
    ok &= require_text("one coast is limited to 16 messages total", override,
                       "#defineINERTIA_MAX_MESSAGES16");
    ok &= require_text("coast starting speed is limited to 1200 units per second", override,
                       "#defineINERTIA_MAX_SPEED1200.0");
    ok &= require_text("the shared coast message counter is stored", override,
                       "unsignedintmessage_count;");
    ok &= require_text("a new coast resets travel and message counts", override,
                       "si->travel_x=si->travel_y=0;si->message_count=0;");
    ok &= require_text("whole-unit packet excess is discarded", stack,
                       "intavailable=(int)*remainder;intremaining=INERTIA_MAX_TRAVEL-*travel;"
                       "intdelta;*remainder-=available;");
    ok &= require_text("packet output is clamped to one quarter notch", stack,
                       "if(available>INERTIA_MAX_PACKET)delta=INERTIA_MAX_PACKET;"
                       "elseif(available<-INERTIA_MAX_PACKET)delta=-INERTIA_MAX_PACKET;");
    ok &= require_text("travel is counted separately per axis", stack,
                       "*travel+=abs(delta);if(*travel>=INERTIA_MAX_TRAVEL)"
                       "*remainder=*velocity=0.0;");
    ok &= require_text("measured starting speed is clamped before coasting", stack,
                       "if(speed>INERTIA_MAX_SPEED){vx*=INERTIA_MAX_SPEED/speed;"
                       "vy*=INERTIA_MAX_SPEED/speed;}");
    ok &= require_text("full elapsed time is retained for decay", stack,
                       "if(!(elapsed_ms=now-si->last_tick))return;");
    ok &= require_text("only the newest bounded frame is integrated", stack,
                       "frame_ms=elapsed_ms>INERTIA_MAX_FRAME_MS?INERTIA_MAX_FRAME_MS:elapsed_ms;"
                       "elapsed_dt=elapsed_ms/1000.0;frame_dt=frame_ms/1000.0;");
    ok &= require_text("vertical output checks the total message budget", override,
                       "if(si->message_count<INERTIA_MAX_MESSAGES&&"
                       "(delta=pointer_inertia_packet(&si->rem_y,&si->vy,&si->travel_y)))"
                       "{si->message_count++;");
    ok &= require_text("horizontal output checks the remaining message budget", override,
                       "if(si->message_count<INERTIA_MAX_MESSAGES&&"
                       "(delta=pointer_inertia_packet(&si->rem_x,&si->vx,&si->travel_x)))"
                       "{si->message_count++;");
    if (count_occurrences(override, "si->message_count++;") != 2)
    {
        fail("each coast packet consumes one total message slot", "expected exactly two guarded send paths");
        ok = 0;
    }
    ok &= require_text("coasting stops when the message budget is used", override,
                       "if(si->message_count>=INERTIA_MAX_MESSAGES||");
    if (ok) pass("coast frame, packet, travel, and total-message limits are active");
}

static void check_inertia_generation(const char *stack, const char *override)
{
    int ok = 1;

    ok &= require_text("pointer input uses one process-wide generation", stack,
                       "staticpthread_mutex_tpointer_input_mutex=PTHREAD_MUTEX_INITIALIZER;"
                       "staticvolatileLONGpointer_input_serial;");
    ok &= require_text("a sample compares its prior generation", override,
                       "previous_serial=InterlockedCompareExchange(&pointer_input_serial,0,0);"
                       "current=si->state==INERTIA_TRACKING&&si->sourceid==sourceid&&"
                       "si->hwnd==hwnd&&si->input_serial==previous_serial;");
    ok &= require_text("an accepted sample advances the generation", override,
                       "input_serial=InterlockedIncrement(&pointer_input_serial);"
                       "pthread_mutex_unlock(&pointer_input_mutex);new_sequence=!current;");
    ok &= require_text("a non-current sample clears old history", override,
                       "if(!current&&si->state!=INERTIA_IDLE){HWNDold_hwnd=si->hwnd;"
                       "si->state=INERTIA_IDLE;si->count=0;si->pos=0;");
    ok &= require_text("a new sequence stores only its own point", override,
                       "if(new_sequence)si->anchor=anchor;");
    ok &= require_text("release validates and advances the same generation", override,
                       "current=si->state==INERTIA_TRACKING&&si->sourceid==sourceid&&"
                       "si->hwnd==hwnd&&si->input_serial==input_serial;"
                       "input_serial=InterlockedIncrement(&pointer_input_serial);");
    ok &= require_text("ticks reject a superseded tracker", stack,
                       "if(si->state!=INERTIA_IDLE&&si->input_serial!="
                       "InterlockedCompareExchange(&pointer_input_serial,0,0)){"
                       "si->state=INERTIA_IDLE;si->count=0;inertia_nudge_stop(si->hwnd);return;}");
    ok &= require_text("guarded submission rejects a stale generation", override,
                       "if(*expected_serial!=InterlockedCompareExchange(&pointer_input_serial,0,0))"
                       "{pthread_mutex_unlock(&pointer_input_mutex);returnFALSE;}");
    ok &= require_text("hardware-input status is normalised to Boolean success", override,
                       "ret=!NtUserSendHardwareInput(hwnd,SEND_HWMSG_RAWINPUT|SEND_HWMSG_FIXED_POSITION|");
    ok &= require_text("vertical coast output carries the saved generation", override,
                       "send_wheel_at_input(si->hwnd,si->anchor,MOUSEEVENTF_WHEEL,delta,now,"
                       "&si->input_serial,FALSE)");
    ok &= require_text("horizontal coast output carries the saved generation", override,
                       "send_wheel_at_input(si->hwnd,si->anchor,MOUSEEVENTF_HWHEEL,delta,now,"
                       "&si->input_serial,FALSE)");
    ok &= forbid_text_between("stale output cannot invalidate newer input", override,
                              "staticBOOLsend_wheel_at_input(", "staticBOOLpointer_button_down(",
                              "InterlockedIncrement(");
    if (ok) pass("new pointer input invalidates older tracking and coast output");
}

static void check_button_serial_and_middle_mode(const char *override)
{
    int ok = 1;

    ok &= require_text("the driver reports every physical button early", override,
                       "SERVER_START_REQ(update_driver_button){req->win=wine_server_user_handle(hwnd);"
                       "req->button=button;req->state=pinch_button_is_wheel(button)?-1:down;");
    ok &= require_text_between("every core press is recorded before range handling", override,
                               "TRACE(\"hwnd%p/%lxbutton%upos%s\\n\"",
                               "if(button>=NB_BUTTONS)returnFALSE;",
                               "notify_button_transition(hwnd,event->button,TRUE);");
    if (count_occurrences(override, "notify_button_transition(hwnd,event->button,FALSE);") != 3)
    {
        fail("every core release path clears early state",
             "expected unknown-button, middle-drag, and ordinary release notifications");
        ok = 0;
    }
    ok &= require_text("the server accepts early button updates", override,
                       "DECL_HANDLER(update_driver_button)");
    ok &= require_text("invalid early button reports are rejected", override,
                       "if(!req->button||req->state<-1||req->state>1){"
                       "set_error(STATUS_INVALID_PARAMETER);return;}");
    ok &= require_text("all physical buttons map to a tracked bucket", override,
                       "case1:return0;case2:return1;case3:return2;case8:return3;"
                       "case9:return4;default:return5;");
    ok &= require_text("early button counts cannot wrap to released", override,
                       "if(shared->driver_button_count[bucket]!=0xff)"
                       "shared->driver_button_count[bucket]++;"
                       "elseshared->driver_button_overflow|=1u<<bucket;");
    ok &= require_text("overflowed early state remains held", override,
                       "elseif(!(shared->driver_button_overflow&(1u<<bucket))&&"
                       "shared->driver_button_count[bucket])shared->driver_button_count[bucket]--;");
    ok &= require_text("every early report advances the serial", override,
                       "advance_mouse_button_serial(desktop);release_object(desktop);");

    if (count_occurrences(override, "time,NULL,TRUE);") != 2)
    {
        fail("only two live middle-drag sends request the exception",
             "expected vertical and horizontal middle_drag_motion sends only");
        ok = 0;
    }
    ok &= require_text("vertical live middle drag requests the exception", override,
                       "send_wheel_at_input(drag->hwnd,drag->origin,MOUSEEVENTF_WHEEL,-delta_y,"
                       "time,NULL,TRUE)");
    ok &= require_text("horizontal live middle drag requests the exception", override,
                       "send_wheel_at_input(drag->hwnd,drag->origin,MOUSEEVENTF_HWHEEL,delta_x,"
                       "time,NULL,TRUE)");
    ok &= require_text("the helper adds the middle-drag flag only on request", override,
                       "(middle_drag?SEND_HWMSG_MIDDLE_DRAG:0),&input,0);");
    ok &= require_text("the server derives the narrow middle-drag mode", override,
                       "boolmiddle_drag=!!(req->flags&SEND_HWMSG_MIDDLE_DRAG);"
                       "unsignedintfixed_position=req->flags&SEND_HWMSG_FIXED_POSITION?"
                       "(middle_drag?HWMSG_FIXED_POSITION_MIDDLE_DRAG:"
                       "HWMSG_FIXED_POSITION_NO_BUTTONS):HWMSG_FIXED_POSITION_NONE;");
    ok &= require_text("invalid middle-drag flag combinations are rejected", override,
                       "if(middle_drag&&(!(req->flags&SEND_HWMSG_FIXED_POSITION)||force_mk_control||"
                       "origin!=IMO_HARDWARE||req->input.type!=INPUT_MOUSE||"
                       "(req->input.mouse.flags!=MOUSEEVENTF_WHEEL&&"
                       "req->input.mouse.flags!=MOUSEEVENTF_HWHEEL))){"
                       "set_error(STATUS_INVALID_PARAMETER);return;}");
    ok &= require_text("ordinary fixed output requires no early buttons", override,
                       "if(fixed_position==HWMSG_FIXED_POSITION_NO_BUTTONS)expected_mask=0;");
    ok &= require_text("middle-drag output requires exactly the middle mask", override,
                       "elseif(fixed_position==HWMSG_FIXED_POSITION_MIDDLE_DRAG)expected_mask=1u<<1;"
                       "elsereturn1;");
    ok &= require_text("server gates require unchanged serial and exact mask", override,
                       "if(button_serial!=current_serial||desktop_shm->driver_button_mask!=expected_mask)"
                       "return1;");
    ok &= require_text("server gates reject all Win32 button state", override,
                       "(desktop_shm->keystate[VK_LBUTTON]|desktop_shm->keystate[VK_MBUTTON]|"
                       "desktop_shm->keystate[VK_RBUTTON]|desktop_shm->keystate[VK_XBUTTON1]|"
                       "desktop_shm->keystate[VK_XBUTTON2])&0x80)return1;");
    ok &= require_text("server middle mode requires one non-overflowed Button2", override,
                       "if(expected_mask&&(desktop_shm->driver_button_count[1]!=1||"
                       "(desktop_shm->driver_button_overflow&expected_mask)))return1;");
    ok &= require_text("client gates require the same exact mask", override,
                       "stale=desktop_shm->mouse_button_serial!=button_serial||"
                       "desktop_shm->driver_button_mask!=expected_mask||");
    ok &= require_text("client middle mode requires one non-overflowed Button2", override,
                       "(expected_mask&&(desktop_shm->driver_button_count[1]!=1||"
                       "(desktop_shm->driver_button_overflow&expected_mask)));");
    if (count_occurrences(override, "fixed_wheel_is_stale(fixed_position,fixed_button_serial)") != 4)
    {
        fail("client delivery rechecks fixed wheel mode after every delay",
             "expected entry, two process-return, and post-hook checks");
        ok = 0;
    }
    if (count_occurrences(override, "fixed_wheel_is_stale(") < 8)
    {
        fail("server and client both enforce fixed wheel mode",
             "expected definitions plus initial, post-hook, dequeue, and client checks");
        ok = 0;
    }
    ok &= require_text("fixed messages carry their mode and button serial", override,
                       "msg->fixed_button_serial=desktop->mouse_button_serial;"
                       "msg_data->fixed_position=fixed_position;"
                       "msg_data->fixed_button_serial=msg->fixed_button_serial;");
    if (ok) pass("only an exact live Button2 drag can use the middle-drag exception");
}

struct safe_axis
{
    double velocity;
    double remainder;
    unsigned int travel;
};

/* Reference the safety envelope, not the production curve implementation. */
static int safe_axis_tick(struct safe_axis *axis, unsigned int elapsed_ms, double rate)
{
    unsigned int frame_ms, remaining;
    double post_velocity, pre_frame_velocity, displacement;
    int raw, packet;

    if (!elapsed_ms || !axis->velocity || axis->travel >= MAX_TRAVEL_VALUE) return 0;
    frame_ms = elapsed_ms < MAX_FRAME_MS_VALUE ? elapsed_ms : MAX_FRAME_MS_VALUE;
    post_velocity = axis->velocity * exp(-rate * elapsed_ms / 1000.0);
    pre_frame_velocity = post_velocity * exp(rate * frame_ms / 1000.0);
    displacement = (pre_frame_velocity - post_velocity) / rate;
    axis->velocity = post_velocity;
    axis->remainder += displacement;

    raw = (int)axis->remainder;
    if (raw > MAX_PACKET_VALUE)
    {
        packet = MAX_PACKET_VALUE;
        axis->remainder = 0.0;
    }
    else if (raw < -MAX_PACKET_VALUE)
    {
        packet = -MAX_PACKET_VALUE;
        axis->remainder = 0.0;
    }
    else
    {
        packet = raw;
        axis->remainder -= raw;
    }
    remaining = MAX_TRAVEL_VALUE - axis->travel;
    if ((unsigned int)abs(packet) > remaining)
    {
        packet = packet < 0 ? -(int)remaining : (int)remaining;
        axis->remainder = 0.0;
    }
    axis->travel += (unsigned int)abs(packet);
    if (axis->travel == MAX_TRAVEL_VALUE)
        axis->velocity = axis->remainder = 0.0;
    return packet;
}

static void check_math_envelope(void)
{
    struct safe_axis normal = {MAX_SPEED_VALUE, 0.0, 0};
    struct safe_axis stalled = {MAX_SPEED_VALUE, 0.0, 0};
    struct safe_axis overflow = {1000000000.0, 0.0, 0};
    struct safe_axis reverse = {-1000000000.0, 0.0, 0};
    struct safe_axis axes[2] = {{1000000000.0, 0.0, 0}, {1000000000.0, 0.0, 0}};
    double expected_velocity, expected_normal;
    unsigned int messages = 0;
    int packet, next, total = 0, i, axis;

    packet = safe_axis_tick(&normal, 8, 4.0);
    expected_normal = MAX_SPEED_VALUE / 4.0 * (1.0 - exp(-4.0 * 0.008));
    if (packet != (int)expected_normal || abs(packet) > MAX_PACKET_VALUE)
        fail("maximum starting speed stays below the packet ceiling", "normal first packet was too large");
    else
        pass("maximum starting speed produces a bounded normal first packet");

    packet = safe_axis_tick(&stalled, 1000, 4.0);
    expected_velocity = MAX_SPEED_VALUE * exp(-4.0);
    if (abs(packet) > MAX_PACKET_VALUE || fabs(stalled.velocity - expected_velocity) > 0.000001)
        fail("a delayed tick cannot catch up missed movement", "stall envelope was exceeded");
    else
        pass("a delayed tick decays fully without replaying missed frames");

    packet = safe_axis_tick(&overflow, 8, 4.0);
    overflow.velocity = 0.0;
    next = safe_axis_tick(&overflow, 8, 4.0);
    if (packet != MAX_PACKET_VALUE || next || overflow.remainder != 0.0)
        fail("positive packet excess is discarded", "excess survived as later output");
    else
        pass("positive packet excess is discarded");

    packet = safe_axis_tick(&reverse, 8, 4.0);
    reverse.velocity = 0.0;
    next = safe_axis_tick(&reverse, 8, 4.0);
    if (packet != -MAX_PACKET_VALUE || next || reverse.remainder != 0.0)
        fail("negative packet excess is discarded", "excess survived as later output");
    else
        pass("negative packet excess is discarded");

    for (i = 0; i < 1000; i++)
    {
        for (axis = 0; axis < 2 && messages < MAX_MESSAGES_VALUE; axis++)
        {
            packet = safe_axis_tick(&axes[axis], 8, 4.0);
            if (!packet) continue;
            messages++;
            total += abs(packet);
        }
        if (messages == MAX_MESSAGES_VALUE) break;
    }
    if (messages != MAX_MESSAGES_VALUE || total != MAX_TOTAL_VALUE ||
        axes[0].travel != MAX_TRAVEL_VALUE || axes[1].travel != MAX_TRAVEL_VALUE ||
        safe_axis_tick(&axes[0], 8, 4.0) || safe_axis_tick(&axes[1], 8, 4.0))
        fail("one coast obeys the combined message budget", "combined envelope was exceeded");
    else
        pass("one coast emits at most 240 units in 16 bounded messages");
}

int main(int argc, char **argv)
{
    static const char *const defaults[] =
    {
        "patches/0090-winex11-preserve-precision-scrolling-from-XInput2-scroll-.patch",
        "patches/0091-winex11-coast-scrolling-and-thrown-middle-drags-after-rel.patch",
        "patches/0074-winex11-server-report-a-touchpad-pinch-as-Ctrl-tagged-whe.patch",
        "patches/0072-winex11-registry-pointer-settings-and-middle-button-dra.patch",
        "patches/0092-winex11-bound-and-isolate-pointer-gesture-output.patch"
    };
    struct text stack_source = {0}, override_source = {0};
    const char *paths[5];
    char *stack, *override;
    int i;

    if (argc != 1 && argc != 6)
    {
        fprintf(stderr, "usage: %s [0090 0091 0074 0072 0092]\n", argv[0]);
        return 2;
    }
    for (i = 0; i < 5; i++) paths[i] = argc == 6 ? argv[i + 1] : defaults[i];
    for (i = 0; i < 5; i++)
        if (!read_patch_new_side(paths[i], &stack_source)) return 2;
    if (!read_patch_new_side(paths[4], &override_source)) return 2;

    stack = compact(stack_source.data ? stack_source.data : "");
    override = compact(override_source.data ? override_source.data : "");
    if (!stack || !override)
    {
        fprintf(stderr, "FAIL: out of memory while compacting patch sources\n");
        free(stack_source.data);
        free(override_source.data);
        free(stack);
        free(override);
        return 2;
    }

    check_pointer_setting_fallback(stack, override);
    check_held_and_direct_input(stack, override);
    check_direct_packet_bounds(stack, override);
    check_delivered_samples_and_stops(stack, override);
    check_accumulator_routing(override);
    check_inertia_limits(stack, override);
    check_inertia_generation(stack, override);
    check_button_serial_and_middle_mode(override);
    check_math_envelope();

    free(stack_source.data);
    free(override_source.data);
    free(stack);
    free(override);
    if (failures)
    {
        fprintf(stderr, "pointer safety checks: %u failure%s\n",
                failures, failures == 1 ? "" : "s");
        return 1;
    }
    puts("pointer safety checks: PASS");
    return 0;
}
