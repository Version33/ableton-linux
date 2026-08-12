#define _POSIX_C_SOURCE 200809L

/*
 * Deterministic source and maths checks for pointer-output safety.
 *
 * Wine is carried here as a patch stack rather than directly linkable source.
 * Read context and added hunk lines from the original patches. Treat 0092 as
 * the guarded-delivery layer, 0094 as the warp layer, and 0095 as the final
 * gesture-policy layer. Removed lines and commit prose cannot satisfy a check.
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
#define MAX_TRAVEL_VALUE (4 * WHEEL_DELTA_VALUE)
#define MAX_MESSAGES_VALUE 192
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

static size_t count_occurrences_between(const char *text, const char *begin,
                                        const char *end, const char *needle)
{
    const char *first = strstr(text, begin), *last, *match;
    size_t count = 0, length = strlen(needle);

    if (!first || !(last = strstr(first, end))) return (size_t)-1;
    for (match = first; (match = strstr(match, needle)) && match < last; match += length)
        count++;
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

static int require_order(const char *test, const char *text, const char *first,
                         const char *second)
{
    const char *a = strstr(text, first), *b;

    if (a && (b = strstr(a, second)) && b > a) return 1;
    fail(test, !a ? first : second);
    return 0;
}

static void check_pointer_setting_fallback(const char *stack, const char *safety,
                                           const char *final)
{
    int ok = 1;

    ok &= require_text("pointer settings use safe source fallback", safety,
                       "staticconstchar*constsources[]={\"environment\",\"AppDefaultsregistry\","
                       "\"globalregistry\"};");
    ok &= require_text("application and global settings are read separately", safety,
                       "key=source_index==1?appkey:defkey;");
    if (count_occurrences(safety, "for(source_index=0;source_index<3;source_index++)") != 2)
    {
        fail("pointer settings try every available source",
             "expected one loop for named settings and one for InertiaRate");
        ok = 0;
    }
    if (count_occurrences(stack, "pointer_option_enum(defkey,appkey,") < 6)
    {
        fail("the original six named pointer settings use fallback",
             "one or more named settings bypass fallback");
        ok = 0;
    }
    ok &= require_text("SmoothScrolling uses named-setting fallback", stack,
                       "pointer_option_enum(defkey,appkey,\"SmoothScrolling\","
                       "\"WINE_X11_SMOOTH_SCROLLING\"");
    ok &= require_text("TouchpadInertia uses named-setting fallback", stack,
                       "pointer_option_enum(defkey,appkey,\"TouchpadInertia\","
                       "\"WINE_X11_TOUCHPAD_INERTIA\"");
    ok &= require_text("PinchZoom uses named-setting fallback", stack,
                       "pointer_option_enum(defkey,appkey,\"PinchZoom\",\"WINE_X11_PINCH_ZOOM\"");
    ok &= require_text("MiddleDrag uses named-setting fallback", stack,
                       "pointer_option_enum(defkey,appkey,\"MiddleDrag\",\"WINE_X11_MIDDLE_DRAG\"");
    ok &= require_text("InertiaCurve uses named-setting fallback", stack,
                       "pointer_option_enum(defkey,appkey,\"InertiaCurve\","
                       "\"WINE_X11_INERTIA_CURVE\"");
    ok &= require_text("WarpEmulation uses named-setting fallback", stack,
                       "pointer_option_enum(defkey,appkey,\"WarpEmulation\","
                       "\"WINE_X11_WARP_EMULATION\"");
    ok &= require_text("named settings are case-insensitive", final,
                       "if(strcasecmp(buffer,names[i]))continue;");
    ok &= require_text("off and zero alias a disabled setting", final,
                       "if(!strcasecmp(names[0],\"disabled\")&&"
                       "(!strcasecmp(buffer,\"off\")||!strcmp(buffer,\"0\")))");
    ok &= require_text("invalid named settings use the diagnostic channel", final,
                       "WARN_(winediag)(\"unrecognized%svalue%sfromthe%s,ignoringit\\n\","
                       "name,debugstr_a(buffer),source);");
    ok &= require_text("invalid inertia rates use the diagnostic channel", final,
                       "WARN_(winediag)(\"InertiaRatevalue%sfromthe%sisnotadecimalin[0.5,16.0],ignoringit\\n\","
                       "debugstr_a(buffer),source);continue;");
    ok &= require_text("a valid inertia rate ends the search", safety,
                       "pointer_config.inertia_rate=parsed;"
                       "TRACE(\"InertiaRate=%.2f(%s)\\n\",parsed,source);break;");
    ok &= require_text("disabled remains a valid inertia setting", stack,
                       "staticconstchar*constinertia_names[]={\"disabled\",\"auto\",\"enabled\"};");
    ok &= require_text("middle throw has an independent setting", final,
                       "pointer_option_enum(defkey,appkey,\"MiddleDragThrow\","
                       "\"WINE_X11_MIDDLE_DRAG_THROW\"");
    ok &= require_text("held-button wheel input has an independent setting", final,
                       "pointer_option_enum(defkey,appkey,\"WheelWhileButtonHeld\","
                       "\"WINE_X11_WHEEL_WHILE_BUTTON_HELD\"");
    ok &= require_text("fine inertia is enabled by default", final,
                       ".touchpad_inertia=POINTER_INERTIA_ENABLED");
    ok &= require_text("middle throw is enabled by default", final,
                       ".middle_drag_throw=POINTER_MIDDLE_DRAG_THROW_ENABLED");
    ok &= require_text("physical wheel input while held remains enabled by default", final,
                       ".wheel_while_button_held=POINTER_WHEEL_WHILE_BUTTON_HELD_ENABLED");
    if (ok) pass("all eight named settings plus InertiaRate preserve safe source fallback");
}

static void check_warp_emulation(const char *stack, const char *warp)
{
    int ok = 1;

    ok &= require_text("warp state is process-wide and locked", warp,
                       "staticpthread_mutex_twarp_emulation_mutex=PTHREAD_MUTEX_INITIALIZER;");
    ok &= forbid_text("warp state does not return to the X11 thread struct", warp,
                      "warp_have_last");
    ok &= forbid_text("warp state has no event-count timeout", warp, "warp_idle");
    ok &= forbid_text("warp state has no polling-rate-dependent backstop", warp, ">512");

    ok &= require_text("warp emulation remains opt-in until the hardware matrix is complete", stack,
                       ".warp_emulation=POINTER_WARP_DISABLED");
    ok &= require_text("warp emulation has a registry setting and environment escape hatch", stack,
                       "pointer_option_enum(defkey,appkey,\"WarpEmulation\","
                       "\"WINE_X11_WARP_EMULATION\"");
    ok &= require_text("warp setting exposes disabled auto and forced modes", stack,
                       "staticconstchar*constwarp_names[]={\"disabled\",\"auto\",\"enabled\"};");
    ok &= require_text("automatic warp handling is limited to XWayland", warp,
                       "XQueryExtension(display,\"XWAYLAND\"");

    ok &= require_order("the pre-warp server point is sampled before XWarpPointer", warp,
                        "XQueryPointer(data->display,root_window", "XWarpPointer(data->display");
    ok &= require_text("extended held buttons survive the core-mask reconciliation", warp,
                       "buttons|=warp_emulation.buttons&~7u;");
    ok &= require_text("only one ordinary held button can arm a warp", warp,
                       "if(!(buttons&7u)||(buttons&(buttons-1)))");
    ok &= require_text_between("every new button press resets warp evidence", warp,
                               "staticvoidwarp_emulation_button_press(",
                               "staticvoidwarp_emulation_button_release(",
                               "warp_emulation.failed_votes=0;");
    ok &= require_text_between("every button release resets warp evidence", warp,
                               "staticvoidwarp_emulation_button_release(",
                               "staticBOOLwarp_emulation_available(",
                               "warp_emulation.failed_votes=0;");
    ok &= require_text_between("wheel presses cancel probes without becoming held buttons", warp,
                               "staticvoidwarp_emulation_button_press(",
                               "staticvoidwarp_emulation_button_release(",
                               "if(button_up_flags[index]){bit=1u<<index;"
                               "warp_emulation.buttons|=bit;}");
    ok &= require_text_between("wheel releases cannot disturb held-button ownership", warp,
                               "staticvoidwarp_emulation_button_release(",
                               "staticBOOLwarp_emulation_available(",
                               "if(button_up_flags[index]){bit=1u<<index;"
                               "warp_emulation.buttons&=~bit;}");
    ok &= require_text("every warp keeps a fixed pre-warp baseline", warp,
                       "warp_emulation.prewarp=prewarp;");
    ok &= require_text("raw correlation uses accelerated XI2 values", warp,
                       "warp_emulation_raw_motion(event->display,event->sourceid,event->time,"
                       "x_value*x_scale,y_value*y_scale);");
    ok &= require_text("failed-warp expectation includes the raw delta", warp,
                       "failed.x=warp_emulation.prewarp.x+round(warp_emulation.raw_dx);");
    ok &= require_text("server-applied expectation includes the same raw delta", warp,
                       "applied.x=warp_emulation.target.x+round(warp_emulation.raw_dx);");
    ok &= require_text("raw evidence is tied to one warp generation", warp,
                       "warp_emulation.raw_generation!=warp_emulation.generation");
    ok &= require_text("raw evidence is tied to the cooked event connection", warp,
                       "warp_emulation.raw_display!=display||warp_emulation.raw_time!=time");
    ok &= require_text("conflicting raw sources keep automatic mode native", warp,
                       "elsewarp_emulation.raw_conflict=TRUE;");
    ok &= require_text("automatic mode needs two failed correlations", warp,
                       "#defineWARP_EMULATION_FAILURE_VOTES2");
    ok &= require_text("successful or ambiguous evidence returns to native mapping", warp,
                       "warp_emulation.failed_votes=0;warp_emulation.reporting=FALSE;");
    ok &= require_text("mapped motion uses the fixed pre-warp point without losing a delta", warp,
                       "warp_emulation.reported.x=warp_emulation.target.x+pos.x-"
                       "warp_emulation.prewarp.x;");

    ok &= require_order("synthetic warp motion is rejected before it can vote", warp,
                        "if(is_old_motion_event(event->serial))", "warp_emulation_reconcile_motion");
    ok &= require_order("cross-thread synthetic warp motion is rejected before reconciliation", warp,
                        "if(warp_emulation_ignore_synthetic(pt))returnFALSE;",
                        "warp_emulation_reconcile_motion(event->state);");
    ok &= require_text("every cross-thread synthetic target copy is rejected", warp,
                       "warp_emulation.synthetic_pending&&pos.x==warp_emulation.target.x&&"
                       "pos.y==warp_emulation.target.y)ignore=TRUE;");
    ok &= require_text("the first non-target cooked motion ends synthetic filtering", warp,
                       "elseif(warp_emulation.synthetic_pending)"
                       "warp_emulation.synthetic_pending=FALSE;");
    ok &= require_order("middle navigation consumes native coordinates before warp mapping", warp,
                        "if(middle_drag_motion(event,pt,time))returnTRUE;",
                        "pt=map_emulated_warp_coords(event->display,pt,event->time,TRUE);");
    ok &= require_order("release coordinates are mapped before warp state is cleared", warp,
                        "pt=map_emulated_warp_coords(event->display,pt,event->time,FALSE);",
                        "warp_emulation_button_release(event->button);");
    ok &= require_order("middle release cannot leave warp emulation armed", warp,
                        "warp_emulation_button_release(event->button);",
                        "if(middle_drag_end(event,pt,time))");
    ok &= require_text("extended press buttons are checked before warp bookkeeping", warp,
                       "if(button>=NB_BUTTONS)warp_emulation_cancel();"
                       "elsewarp_emulation_button_press(event->button);");
    ok &= require_text("release mapping is limited to real held buttons", warp,
                       "if(button>=NB_BUTTONS)warp_emulation_cancel();else{"
                       "if(button_up_flags[button])"
                       "pt=map_emulated_warp_coords(event->display,pt,event->time,FALSE);"
                       "warp_emulation_button_release(event->button);}");
    ok &= require_order("extended release buttons are checked before array lookup", warp,
                        "if(button>=NB_BUTTONS)warp_emulation_cancel();else{",
                        "if(button_up_flags[button])");
    ok &= require_text("a keyboard-grab refusal disarms an older transform", warp,
                       "if(keyboard_grabbed){warp_emulation_disarm();"
                       "WARN(\"refusingtowarpto%u,%u\\n\",pos.x,pos.y);returnFALSE;}");
    ok &= require_text("a pointer-grab refusal disarms an older transform", warp,
                       "!=GrabSuccess){warp_emulation_disarm();"
                       "WARN(\"refusingtowarppointerto%u,%uwithoutexclusivegrab\\n\","
                       "pos.x,pos.y);returnFALSE;}");

    ok &= require_text("clip release cancels warp state before an early return", warp,
                       "warp_emulation_cancel();if(!clip_window)return;");
    ok &= require_text("capture transitions cancel before the flags early return", warp,
                       "warp_emulation_cancel();"
                       "if(!(flags&(GUI_INMOVESIZE|GUI_INMENUMODE)))return;");
    ok &= require_text("FocusOut cancellation runs before focus guards", warp,
                       "if(event->detail!=NotifyPointer)warp_emulation_cancel();"
                       "if(event->detail==NotifyPointer)");
    ok &= require_text("device replacement cancels warp state", warp,
                       "if(event->deviceid!=data->xinput2_pointer)returnFALSE;"
                       "warp_emulation_cancel();update_relative_valuators");
    ok &= require_text("thread detach cancels process warp state", warp,
                       "if(data){warp_emulation_cancel();");

    if (ok) pass("XWayland warp emulation activates only from correlated failed warps");
}

static void check_held_and_direct_input(const char *stack, const char *safety,
                                        const char *final)
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
    ok &= forbid_text("held movement cannot become notched output", safety,
                      "POINTER_SCROLL_NOTCHED||buttons_down");
    ok &= require_text("held wheel input requires enabled mode and exact provenance", final,
                       "if(pointer_config.wheel_while_button_held=="
                       "POINTER_WHEEL_WHILE_BUTTON_HELD_ENABLED&&event_button_mask&&"
                       "event_button_mask==held_button_mask&&"
                       "!x11drv_thread_data()->middle_drag.active)");
    ok &= require_text_between("only a stable held physical wheel uses the stock input path", final,
                               "staticBOOLsend_discrete_wheel_input(",
                               "/*Middle-dragnavigation",
                               "returnsend_mouse_input(hwnd,pt,MOUSEEVENTF_ABSOLUTE|flags,"
                               "delta,time,NULL);");
    ok &= require_text_between("mismatched held state is conservatively suppressed", final,
                               "staticBOOLsend_discrete_wheel_input(",
                               "/*Middle-dragnavigation",
                               "if(event_button_mask||held_button_mask||"
                               "x11drv_thread_data()->middle_drag.active)");
    ok &= require_text_between("unheld physical wheel input retains guarded positioning", final,
                               "staticBOOLsend_discrete_wheel_input(",
                               "/*Middle-dragnavigation",
                               "returnsend_wheel_at_input(hwnd,pt,flags,delta,time,NULL,FALSE);");
    ok &= require_text("core wheel provenance includes core and extended-button masks", final,
                       "core_event_button_mask(event->state)|"
                       "(pointer_button_mask()&((1u<<3)|(1u<<4)))");
    ok &= require_text("native XI wheel provenance maps all ordinary buttons", final,
                       "staticconstunsignedintbuttons[]={1,2,3,8,9};");
    ok &= require_text("native XI wheel provenance preserves each mapped bit", final,
                       "XIMaskIsSet(event->buttons.mask,buttons[i]))mask|=1u<<i;");
    ok &= require_text("native XI wheel uses the full event button mask", final,
                       "send_discrete_wheel_input(hwnd,pt,button_down_flags[button],"
                       "(int)button_down_data[button],time,xinput2_ordinary_button_mask(event));");
    ok &= require_text("direct XI scroll separates cursor and wheel submission", safety,
                       "if(!send_mouse_input(hwnd,pt,MOUSEEVENTF_ABSOLUTE,0,time,NULL))returnFALSE;"
                       "returnsend_wheel_at_input(hwnd,pt,flags,delta,time,NULL,FALSE);");
    ok &= forbid_text_between("cursor movement cannot inherit fixed-wheel flags", safety,
                              "staticBOOLsend_xinput2_wheel_input(", "/*Addboundedinertia",
                              "MOUSEEVENTF_ABSOLUTE|flags");
    ok &= require_text("held smooth valuators still reseed without gesture output", final,
                       "if(buttons_down||discontinuity){");
    if (ok) pass("only provenance-matched physical wheel input bypasses fixed gesture delivery");
}

static void check_legacy_wheel_copy_guard(const char *final)
{
    int ok = 1;

    ok &= require_text("legacy wheel-copy correlation is per X11 thread", final,
                       "structx11drv_legacy_wheel_copylegacy_wheel_copy;");
    ok &= require_text_between("legacy wheel-copy tags retain raw X time", final,
                               "structx11drv_legacy_wheel_copy{",
                               "externvoidpointer_scroll_invalidate_baselines", "Timetime;");
    ok &= require_text_between("legacy wheel-copy tags retain expected directions", final,
                               "structx11drv_legacy_wheel_copy{",
                               "externvoidpointer_scroll_invalidate_baselines",
                               "unsignedintwheel_buttons;");
    ok &= require_text_between("legacy wheel-copy tags retain the held mask", final,
                               "structx11drv_legacy_wheel_copy{",
                               "externvoidpointer_scroll_invalidate_baselines",
                               "unsignedintheld_buttons;");
    ok &= require_text_between("legacy wheel-copy tags retain the X target window", final,
                               "structx11drv_legacy_wheel_copy{",
                               "externvoidpointer_scroll_invalidate_baselines", "Windowwindow;");
    ok &= require_text("an emulated XI report without held buttons cannot arm suppression", final,
                       "if(!held_buttons){legacy_wheel_copy_reset("
                       "\"emulatedXIreporthasnoheldordinarybutton\");return;}");
    ok &= require_text("vertical legacy directions come from the changed XI axis", final,
                       "legacy_wheel_copy_direction(&src->scroll_y,value_y,4,5)");
    ok &= require_text("horizontal legacy directions come from the changed XI axis", final,
                       "legacy_wheel_copy_direction(&src->scroll_x,value_x,6,7)");
    ok &= require_text("a tag generation is keyed by time held mask and target window", final,
                       "if(!copy->valid||copy->time!=event->time||"
                       "copy->held_buttons!=held_buttons||copy->window!=event->event)");
    ok &= require_text("a new tag generation clears all prior correlation state", final,
                       "if(copy->valid)legacy_wheel_copy_reset(\"newemulatedXIreport\");"
                       "copy->time=event->time;");
    ok &= require_text("a later directionless XI report expires an older tag", final,
                       "if(copy->valid&&copy->time!=event->time)legacy_wheel_copy_reset("
                       "\"newemulatedXIreporthasnolegacycopy\");");
    ok &= require_text("a tag stores the raw XI time mask and target", final,
                       "copy->time=event->time;copy->held_buttons=held_buttons;"
                       "copy->window=event->event;copy->wheel_buttons=0;copy->valid=TRUE;");
    ok &= require_order("the emulated XI tag is captured before baselines advance", final,
                        "legacy_wheel_copy_tag(event,src,have_x,value_x,have_y,value_y);",
                        "if(have_x)smooth_scroll_delta(&src->scroll_x,value_x,TRUE,FALSE,NULL);");
    ok &= require_text_between("only an emulated XI scroll report arms a legacy tag", final,
                               "if(emulated){", "/*Forwardco-reportedpointermotion",
                               "legacy_wheel_copy_tag(event,src,have_x,value_x,have_y,value_y);");

    ok &= require_text("a different raw X timestamp expires the tag", final,
                       "if(event->time!=copy->time){legacy_wheel_copy_reset("
                       "\"legacycorewheeltimechanged\");returnFALSE;}");
    ok &= require_text("only matching direction time window held state and server events suppress", final,
                       "if(event->send_event||event->window!=copy->window||"
                       "!(copy->wheel_buttons&button_bit)||!held_buttons||"
                       "held_buttons!=copy->held_buttons)");
    ok &= forbid_text_between("one same-time smooth report may suppress all of its legacy copies", final,
                              "staticBOOLlegacy_wheel_copy_suppress(",
                              "staticvoidlegacy_wheel_copy_button_release(",
                              "copy->wheel_buttons&=");
    ok &= require_text("tagged legacy copies are rejected before physical-wheel routing", final,
                       "if(legacy_wheel_copy_suppress(event,event_button_mask)){"
                       "pinch_button_release(event->button);returnTRUE;}"
                       "#endifsend_discrete_wheel_input(");

    ok &= require_text("ordinary button presses reset a pending legacy tag", final,
                       "if(!pinch_button_is_wheel(event->button))legacy_wheel_copy_reset("
                       "\"corebuttonpressboundary\");");
    ok &= require_text("button releases apply the legacy-tag boundary", final,
                       "legacy_wheel_copy_button_release(event);");
    ok &= require_text("later or non-wheel releases expire a legacy tag", final,
                       "if(!pinch_button_is_wheel(event->button)||event->time!=copy->time)"
                       "legacy_wheel_copy_reset(\"corebuttonreleaseboundary\");");
    ok &= require_text("scroll baseline invalidation expires a legacy tag", final,
                       "legacy_wheel_copy_reset(\"scrollbaselineinvalidation\");");
    ok &= require_text("scroll metadata changes expire a legacy tag", final,
                       "legacy_wheel_copy_reset(\"scrolldevicemetadatachanged\");");
    ok &= require_text("scroll device removal expires a legacy tag", final,
                       "legacy_wheel_copy_reset(\"scrolldeviceremovedordisabled\");");
    if (ok) pass("held-button legacy smooth-scroll copies require exact X event correlation");
}

static void check_direct_packet_bounds(const char *stack, const char *safety,
                                       const char *final)
{
    int ok = 1;

    if (count_occurrences(safety, "staticconstintmax_delta=WHEEL_DELTA;") != 2)
    {
        fail("smooth and pinch reports are each limited to one notch",
             "expected one exact limit in each final decoder");
        ok = 0;
    }
    ok &= require_text("large smooth jumps reset their baseline", safety,
                       "if(fabs(units)>2.0*max_delta){axis->value=value;"
                       "if(discontinuity)*discontinuity=TRUE;return0;}");
    ok &= require_text("smooth excess is discarded after one notch", stack,
                       "if((delta=round(units))>max_delta||delta<-max_delta){axis->value=value;"
                       "returndelta>0?max_delta:-max_delta;}");
    ok &= require_text("middle-drag vertical movement is bounded before delivery", final,
                       "delta_y=middle_drag_delta(&drag->accum_y,notched);");
    ok &= require_text("middle-drag horizontal movement is bounded before delivery", final,
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
    ok &= require_text("unknown mouse buttons also block pinch output", safety,
                       "returnpinch_state.buttons_down||pinch_state.other_buttons_down||"
                       "pinch_state.wheel_requests;");
    ok &= require_text("unknown button counts cannot wrap", safety,
                       "elseif(pinch_state.other_buttons_down!=~0u)pinch_state.other_buttons_down++;");
    if (ok) pass("direct scroll, middle drag, and pinch packets are bounded");
}

static void check_continuation_sources(const char *final)
{
    int ok = 1;

    ok &= require_text("middle continuation has independent enablement", final,
                       "if(kind==POINTER_INERTIA_KIND_MIDDLE_DRAG)returnpointer_config."
                       "middle_drag_throw==POINTER_MIDDLE_DRAG_THROW_ENABLED;");
    ok &= require_text("fine continuation requires enabled mode", final,
                       "returnpointer_config.touchpad_inertia==POINTER_INERTIA_ENABLED;");
    ok &= require_text("middle throw starts with a press-time zero-motion anchor", final,
                       "middle_drag_throw_sample(x11drv_thread_data(),hwnd,pt,0.0,0.0,time);");
    ok &= require_text("middle throw records raw pointer movement", final,
                       "middle_drag_throw_sample(x11drv_thread_data(),drag->hwnd,drag->origin,"
                       "move_x,-move_y,time);");
    ok &= require_order("inside-slop motion is retained for an eventual middle throw", final,
                        "if(move_x||move_y)middle_drag_throw_sample(", "if(!drag->moved)");
    ok &= require_text("a completed middle drag evaluates its release", final,
                       "middle_drag_throw_release(data,drag->hwnd,time);");
    ok &= require_text("a middle click cancels continuation state", final,
                       "elsepointer_inertia_cancel();");
    ok &= require_text("middle throw uses an explicit Button2 release reason", final,
                       "pointer_inertia_release(data,POINTER_INERTIA_KIND_MIDDLE_DRAG,"
                       "INERTIA_SOURCE_MIDDLE_DRAG,hwnd,time,"
                       "POINTER_INERTIA_END_MIDDLE_RELEASE);");
    ok &= require_text("fine and middle estimators have distinct minimum spans", final,
                       "#defineINERTIA_MIN_SPAN_MS10");
    ok &= require_text("middle estimator accepts a short but timed terminal flick", final,
                       "#defineMIDDLE_THROW_MIN_SPAN_MS4");
    ok &= require_text("middle estimator measures its window from physical release", final,
                       "if(release_time-si->history[j].time<=MIDDLE_THROW_HISTORY_MS)"
                       "{start=i?i-1:i;break;}");
    ok &= require_text("middle estimator discards motion before a terminal pause", final,
                       "if(!used||sample_time-previous>MIDDLE_THROW_MAX_GAP_MS)");
    ok &= require_text("middle estimator rejects a jittering or reversed suffix", final,
                       "coherence=path>0.0?distance/path:0.0;"
                       "if(used<2||span<MIDDLE_THROW_MIN_SPAN_MS||"
                       "coherence<MIDDLE_THROW_MIN_COHERENCE)");
    ok &= require_text("raw middle motion converts to wheel units only after estimation", final,
                       "*vx=sum_x*1000.0*WHEEL_DELTA/(span*MIDDLE_DRAG_STEP);"
                       "*vy=sum_y*1000.0*WHEEL_DELTA/(span*MIDDLE_DRAG_STEP);");
    ok &= require_text("middle release uses its own terminal-gap gate", final,
                       "UINTrelease_gate=kind==POINTER_INERTIA_KIND_MIDDLE_DRAG?"
                       "MIDDLE_THROW_MAX_GAP_MS:INERTIA_RELEASE_GATE_MS;");
    ok &= require_text_between("middle tracking never arms the inactivity timer", final,
                               "staticvoidpointer_inertia_record(",
                               "staticvoidpointer_scroll_inertia_activity(",
                               "if(kind==POINTER_INERTIA_KIND_FINE_SCROLL)"
                               "inertia_nudge_arm(hwnd,si->input_serial,INERTIA_DEADLINE_MS);");
    ok &= require_text("stray timer ticks cannot release a middle throw", final,
                       "if(si->kind==POINTER_INERTIA_KIND_MIDDLE_DRAG){"
                       "TRACE(\"middlethrowignoresstraytimertick;awaitingButton2release\\n\");"
                       "return;}");

    ok &= require_text("unchanged scroll input remains the preferred explicit marker", final,
                       "stop_marker=(have_x||have_y)&&");
    ok &= require_text("changed cumulative valuators are tracked before baselines advance", final,
                       "scroll_changed=(have_x&&src->scroll_x.last_value_valid&&"
                       "value_x!=src->scroll_x.last_value)||"
                       "(have_y&&src->scroll_y.last_value_valid&&"
                       "value_y!=src->scroll_y.last_value);");
    ok &= require_order("changed-but-rounded-zero XI2 activity is not discarded", final,
                        "scroll_changed=(have_x&&", "if(have_x){src->scroll_x.last_value=value_x;");
    ok &= require_text("explicit marker wins over changed-scroll activity", final,
                       "if(stop_marker)pointer_inertia_stop_marker(data,event->sourceid,hwnd,time);"
                       "elseif(scroll_changed)pointer_scroll_inertia_activity(");
    ok &= require_text("fine activity records even zero delivered wheel units", final,
                       "pointer_inertia_record(data,POINTER_INERTIA_KIND_FINE_SCROLL,sourceid,hwnd,"
                       "anchor,dx,dy,time);");
    ok &= require_text_between("every accepted activity sample stores its terminal axis and time", final,
                               "staticvoidpointer_inertia_record(",
                               "staticvoidpointer_scroll_inertia_activity(",
                               "si->history[i].dy=dy;si->history[i].time=time;");
    ok &= require_text_between("a discontinuity cancels only prior fine-scroll history", final,
                               "if(buttons_down||discontinuity){",
                               "elseif(pointer_config.smooth_scrolling==POINTER_SCROLL_PRECISE)",
                               "if(!data->middle_drag.active)pointer_inertia_cancel();");
    ok &= require_text_between("a discontinuity zeros both output axes", final,
                               "if(buttons_down||discontinuity){",
                               "elseif(pointer_config.smooth_scrolling==POINTER_SCROLL_PRECISE)",
                               "if(discontinuity)delta_x=delta_y=0;");
    ok &= require_text("fine inactivity fallback requires enabled mode", final,
                       "if(si->kind==POINTER_INERTIA_KIND_FINE_SCROLL&&"
                       "pointer_inertia_enabled(POINTER_INERTIA_KIND_FINE_SCROLL)&&"
                       "now-si->last_time<=2*INERTIA_DEADLINE_MS)");
    ok &= require_text("late inactivity abandons rather than fabricating a coast", final,
                       "else{TRACE(\"%strackingabandonedafter%umsinactive\\n\",");
    ok &= require_text("inactivity fallback uses its distinct conservative reason", final,
                       "pointer_inertia_evaluate(data,now,POINTER_INERTIA_END_XI2_INACTIVITY);");
    ok &= require_text("inactivity needs twice the explicit-marker starting speed", final,
                       "if(reason==POINTER_INERTIA_END_XI2_INACTIVITY)start_speed*=2.0;");
    ok &= require_text("co-reported scroll motion does not split continuation history", final,
                       "if(!co_reported_scroll)pointer_inertia_cancel();");
    ok &= require_text("native XI motion is tagged as part of its scroll frame", final,
                       "if(saw_motion)forward_xinput2_core_event(hwnd,event,TRUE);");
    ok &= require_text("an emulated XI duplicate preserves an active middle throw", final,
                       "if(!data->middle_drag.active)pointer_inertia_cancel();returnTRUE;");
    if (ok) pass("fine inertia and middle throw have independent, explicit end policies");
}

static void check_inertia_timer_initialization(const char *final)
{
    int ok = 1;

    ok &= require_text("the inertia condition starts as uninitialised storage", final,
                       "staticpthread_cond_tinertia_nudge_cond;");
    ok &= forbid_text("the inertia condition is not statically and dynamically initialised", final,
                      "PTHREAD_COND_INITIALIZER");
    if (count_occurrences(final, "pthread_cond_init(&inertia_nudge_cond,&attr)") != 1)
    {
        fail("the inertia condition is initialised exactly once",
             "expected one dynamic condition-variable initialisation");
        ok = 0;
    }

    ok &= require_order("condition attributes are created before selecting a clock", final,
                        "pthread_condattr_init(&attr)",
                        "pthread_condattr_setclock(&attr,CLOCK_MONOTONIC)");
    ok &= require_order("the monotonic clock is selected before condition initialisation", final,
                        "pthread_condattr_setclock(&attr,CLOCK_MONOTONIC)",
                        "pthread_cond_init(&inertia_nudge_cond,&attr)");
    ok &= require_order("condition attributes are destroyed after condition initialisation", final,
                        "pthread_cond_init(&inertia_nudge_cond,&attr)",
                        "pthread_condattr_destroy(&attr)");

    ok &= require_text("attribute initialisation failure disables the timer", final,
                       "if((ret=pthread_condattr_init(&attr))){"
                       "WARN(\"failedtoinitialiseinertiaconditionattributes(%d),"
                       "inertiadisabled\\n\",ret);inertia_nudge.failed=TRUE;}");
    ok &= require_text("clock or condition initialisation failure disables the timer", final,
                       "if((ret=pthread_condattr_setclock(&attr,CLOCK_MONOTONIC))||"
                       "(ret=pthread_cond_init(&inertia_nudge_cond,&attr))){"
                       "WARN(\"failedtoinitialisemonotonicinertiacondition(%d),"
                       "inertiadisabled\\n\",ret);inertia_nudge.failed=TRUE;}"
                       "pthread_condattr_destroy(&attr);");
    ok &= require_text("timer setup failure prevents worker creation", final,
                       "if(!inertia_nudge.failed&&NtCreateThreadEx(&thread,THREAD_ALL_ACCESS,NULL,"
                       "NtCurrentProcess(),inertia_nudge_thread,NULL,0,0,0,0,NULL))");
    ok &= require_text("a failed setup cannot enter the worker-success branch", final,
                       "elseif(!inertia_nudge.failed)");
    ok &= require_order("only the guarded worker-success branch marks the timer running", final,
                        "elseif(!inertia_nudge.failed)", "inertia_nudge.running=TRUE;");
    if (ok) pass("the inertia timer condition is initialised once with a monotonic fail-closed setup");
}

static void check_one_shot_inertia_ticks(const char *final)
{
    static const char tick_begin[] =
        "voidpointer_inertia_tick(LONGinput_serial){"
        "structx11drv_thread_data*data=x11drv_thread_data();";
    static const char coast_begin[] = "caseINERTIA_COASTING:break;}";
    static const char tick_end[] = "UINTtime=EVENT_x11_time_to_win32_time(event->time);";
    size_t count;
    int ok = 1;

    ok &= require_text_between("each timer slot carries its tracker generation", final,
                               "staticpthread_cond_tinertia_nudge_cond;staticstruct{",
                               "for(i=0;i<INERTIA_NUDGE_SLOTS;i++)", "LONGinput_serial;");
    ok &= forbid_text_between("timer slots carry no repeating interval", final,
                              "staticpthread_cond_tinertia_nudge_cond;staticstruct{",
                              "for(i=0;i<INERTIA_NUDGE_SLOTS;i++)", "UINTinterval;");
    ok &= forbid_text_between("timer slots carry no repeating mode", final,
                              "staticpthread_cond_tinertia_nudge_cond;staticstruct{",
                              "for(i=0;i<INERTIA_NUDGE_SLOTS;i++)", "BOOLrepeating;");
    ok &= forbid_text("the final timer has no repeating scheduler state", final, "repeating");
    ok &= require_text("timer arms require an explicit generation", final,
                       "staticvoidinertia_nudge_arm(HWNDhwnd,LONGinput_serial,UINTinterval)");
    ok &= forbid_text("the repeating timer signature cannot return", final,
                      "inertia_nudge_arm(HWNDhwnd,UINTinterval,BOOL");
    ok &= forbid_text("coast arms cannot request a repeating timer", final,
                      "INERTIA_TICK_MS,TRUE");
    ok &= forbid_text("tracking arms cannot use the former Boolean timer mode", final,
                      "INERTIA_DEADLINE_MS,FALSE");

    ok &= require_text_between("the worker snapshots a due slot generation", final,
                               "for(i=0;i<INERTIA_NUDGE_SLOTS;i++){"
                               "HWNDhwnd=inertia_nudge.slots[i].hwnd;LONGinput_serial;BOOLok;",
                               "staticvoidinertia_nudge_arm(",
                               "input_serial=inertia_nudge.slots[i].input_serial;");
    ok &= require_order("the worker snapshots the generation before consuming its slot", final,
                        "input_serial=inertia_nudge.slots[i].input_serial;",
                        "inertia_nudge.slots[i].hwnd=0;");
    ok &= require_order("the worker consumes the slot before posting", final,
                        "inertia_nudge.slots[i].hwnd=0;",
                        "NtUserPostMessage(hwnd,WM_X11DRV_POINTER_TICK,"
                        "(WPARAM)(ULONG)input_serial,0)");
    ok &= require_text("the posted tick carries the captured generation in WPARAM", final,
                       "ok=NtUserPostMessage(hwnd,WM_X11DRV_POINTER_TICK,"
                       "(WPARAM)(ULONG)input_serial,0);");
    ok &= require_text("a post failure only records the consumed generation", final,
                       "if(!ok)TRACE(\"failedtopostpointertickforhwnd%pserial%ld\\n\","
                       "hwnd,(long)input_serial);");
    ok &= forbid_text_between("a post failure cannot clear a replacement schedule", final,
                              "if(!ok)TRACE(", "staticvoidinertia_nudge_arm(",
                              "inertia_nudge.slots[");

    ok &= require_text("the real tick handler accepts a generation", final, tick_begin);
    ok &= forbid_text("the untagged tick handler signature cannot return", final,
                      "pointer_inertia_tick(void)");
    ok &= require_text("the public tick declaration carries the generation", final,
                       "externvoidpointer_inertia_tick(LONGinput_serial);");
    ok &= require_text("the window dispatcher forwards the tick generation", final,
                       "caseWM_X11DRV_POINTER_TICK:pointer_inertia_tick((LONG)wp);return0;");
    ok &= require_text("idle or locally stale ticks return without touching state", final,
                       "if(si->state==INERTIA_IDLE||si->input_serial!=input_serial){"
                       "TRACE(\"stalepointertickserial%ld,current%ldstate%u\\n\","
                       "(long)input_serial,(long)si->input_serial,si->state);return;}");
    ok &= require_order("local stale-tick rejection precedes the process generation check", final,
                        "if(si->state==INERTIA_IDLE||si->input_serial!=input_serial)",
                        "if(si->input_serial!=InterlockedCompareExchange("
                        "&pointer_input_serial,0,0))");
    ok &= forbid_text_between("local stale-tick rejection cannot mutate tracker state", final,
                              "if(si->state==INERTIA_IDLE||si->input_serial!=input_serial)",
                              "if(si->input_serial!=InterlockedCompareExchange(",
                              "si->state=INERTIA_");

    if (count_occurrences(final, "inertia_nudge_arm(") != 6 ||
        count_occurrences(final, "inertia_nudge_arm(hwnd,si->input_serial,") != 1 ||
        count_occurrences(final, "inertia_nudge_arm(si->hwnd,si->input_serial,") != 4)
    {
        fail("every timer arm carries the current tracker generation",
             "expected one definition and five generation-tagged arm calls");
        ok = 0;
    }
    ok &= require_text("a new fine-scroll deadline carries its generation", final,
                       "inertia_nudge_arm(hwnd,si->input_serial,INERTIA_DEADLINE_MS);");
    ok &= require_text("a newly accepted coast tick carries its generation", final,
                       "inertia_nudge_arm(si->hwnd,si->input_serial,INERTIA_TICK_MS);");
    ok &= require_text("an early tracking tick rearms its generation only", final,
                       "inertia_nudge_arm(si->hwnd,si->input_serial,"
                       "INERTIA_DEADLINE_MS-(now-si->last_time));return;");

    ok &= require_text("an elapsed-zero coast rearms before returning", final,
                       "if(!(elapsed_ms=now-si->last_tick)){"
                       "inertia_nudge_arm(si->hwnd,si->input_serial,INERTIA_TICK_MS);return;}");
    ok &= require_text("a continuing coast rearms only at the handler end", final,
                       "elseinertia_nudge_arm(si->hwnd,si->input_serial,INERTIA_TICK_MS);}");
    count = count_occurrences_between(final, coast_begin, tick_end,
                                      "inertia_nudge_arm(si->hwnd,si->input_serial,"
                                      "INERTIA_TICK_MS)");
    if (count != 2)
    {
        fail("coasting rearms only for elapsed-zero and continued output",
             count == (size_t)-1 ? "coasting handler section was not found" :
                                   "unexpected coast rearm site count");
        ok = 0;
    }
    count = count_occurrences_between(final, tick_begin, tick_end, "inertia_nudge_arm(");
    if (count != 3)
    {
        fail("the tick handler has only tracking, elapsed-zero, and terminal rearm sites",
             count == (size_t)-1 ? "tick handler section was not found" :
                                   "unexpected tick-handler arm site count");
        ok = 0;
    }
    if (ok) pass("generation-tagged one-shot ticks cannot backlog or perturb replacement state");
}

static void check_inertia_lifecycle_cancellation(const char *final)
{
    int ok = 1;

    ok &= require_text("DestroyWindow cancels continuation before an unknown-window return", final,
                       "structx11drv_thread_data*thread_data=x11drv_thread_data();"
                       "structx11drv_win_data*data;pointer_inertia_cancel();"
                       "if(!(data=get_win_data(hwnd)))return;");
    ok &= require_text("DestroyNotify cancels continuation before an unknown-window return", final,
                       "structx11drv_win_data*data;BOOLembedded;pointer_inertia_cancel();"
                       "if(!(data=get_win_data(hwnd)))returnFALSE;");
    ok &= require_text("every capture transition cancels continuation before early return", final,
                       "TRACE(\"hwnd%p,flags%#x,previous%p\\n\",hwnd,flags,previous);"
                       "pointer_inertia_cancel();warp_emulation_cancel();"
                       "if(!(flags&(GUI_INMOVESIZE|GUI_INMENUMODE)))return;");
    if (ok) pass("capture and window destruction unconditionally cancel continuation state");
}

static void check_accumulator_routing(const char *safety)
{
    int ok = 1;

    ok &= require_text("accumulated motion has an explicit pending state", safety,
                       "BOOLmouse_motion_pending;");
    ok &= require_text("accumulated motion remembers its routing flags", safety,
                       "UINTmouse_motion_flags;");
    ok &= require_text("empty pending state is checked explicitly", safety,
                       "if(!info->mouse_motion_pending)returnSTATUS_SUCCESS;");
    ok &= require_text("pending motion is flushed with its own flags", safety,
                       "if(info->mouse_motion_pending&&flags!=info->mouse_motion_flags){"
                       "NTSTATUSstatus=send_mouse_motion(info->mouse_motion_flags);if(status)returnstatus;}");
    ok &= require_text("new pending motion stores its flags", safety,
                       "info->mouse_motion_flags=flags;info->mouse_motion_pending=TRUE;");
    ok &= require_text("submitted motion clears its pending state", safety,
                       "info->mouse_motion_flags=0;info->mouse_motion_pending=FALSE;");
    if (ok) pass("queued cursor movement keeps its own routing flags");
}

static void check_inertia_limits(const char *stack, const char *safety, const char *final)
{
    int ok = 1;

    ok &= require_text("coast integration is limited to 16 ms", final,
                       "#defineINERTIA_MAX_FRAME_MS16");
    ok &= require_text("one coast packet is limited to 15 units", final,
                       "#defineINERTIA_MAX_PACKET(WHEEL_DELTA/8)");
    ok &= require_text("each coast axis is limited to four notches", final,
                       "#defineINERTIA_MAX_TRAVEL(4*WHEEL_DELTA)");
    ok &= require_text("one coast is limited to 192 messages total", final,
                       "#defineINERTIA_MAX_MESSAGES192");
    ok &= require_text("the final policy retains the bounded packet helper", final,
                       "staticintpointer_inertia_packet(double*remainder,double*velocity,int*travel)");
    ok &= require_text("the final policy retains the guarded timer tick", final,
                       "voidpointer_inertia_tick(LONGinput_serial)");
    ok &= require_text("coast starting speed is limited to 1200 units per second", safety,
                       "#defineINERTIA_MAX_SPEED1200.0");
    ok &= require_text("the shared coast message counter is stored", safety,
                       "unsignedintmessage_count;");
    ok &= require_text("a new coast resets travel and message counts", safety,
                       "si->travel_x=si->travel_y=0;si->message_count=0;");
    ok &= require_text("whole-unit packet excess is discarded", stack,
                       "intavailable=(int)*remainder;intremaining=INERTIA_MAX_TRAVEL-*travel;"
                       "intdelta;*remainder-=available;");
    ok &= require_text("packet output is clamped to one eighth notch", stack,
                       "if(available>INERTIA_MAX_PACKET)delta=INERTIA_MAX_PACKET;"
                       "elseif(available<-INERTIA_MAX_PACKET)delta=-INERTIA_MAX_PACKET;");
    ok &= require_text("travel is counted separately per axis", stack,
                       "*travel+=abs(delta);if(*travel>=INERTIA_MAX_TRAVEL)"
                       "*remainder=*velocity=0.0;");
    ok &= require_text("measured starting speed is clamped before coasting", stack,
                       "if(speed>INERTIA_MAX_SPEED){vx*=INERTIA_MAX_SPEED/speed;"
                       "vy*=INERTIA_MAX_SPEED/speed;}");
    ok &= require_text("an elapsed-zero tick returns only after rearming", final,
                       "if(!(elapsed_ms=now-si->last_tick)){"
                       "inertia_nudge_arm(si->hwnd,si->input_serial,INERTIA_TICK_MS);return;}");
    ok &= require_text("only the newest bounded frame is integrated", stack,
                       "frame_ms=elapsed_ms>INERTIA_MAX_FRAME_MS?INERTIA_MAX_FRAME_MS:elapsed_ms;"
                       "elapsed_dt=elapsed_ms/1000.0;frame_dt=frame_ms/1000.0;");
    ok &= require_text("vertical output checks the total message budget", safety,
                       "if(si->message_count<INERTIA_MAX_MESSAGES&&"
                       "(delta=pointer_inertia_packet(&si->rem_y,&si->vy,&si->travel_y)))"
                       "{si->message_count++;");
    ok &= require_text("horizontal output checks the remaining message budget", safety,
                       "if(si->message_count<INERTIA_MAX_MESSAGES&&"
                       "(delta=pointer_inertia_packet(&si->rem_x,&si->vx,&si->travel_x)))"
                       "{si->message_count++;");
    if (count_occurrences(safety, "si->message_count++;") != 2)
    {
        fail("each coast packet consumes one total message slot", "expected exactly two guarded send paths");
        ok = 0;
    }
    ok &= require_text("coasting stops when the message budget is used", safety,
                       "if(si->message_count>=INERTIA_MAX_MESSAGES||");
    ok &= require_text("coasting retains the independent four-second backstop", final,
                       "now-si->start_time>INERTIA_CAP_MS+1000");
    if (ok) pass("coast frame, packet, travel, and total-message limits are active");
}

static void check_inertia_generation(const char *stack, const char *safety,
                                     const char *final)
{
    int ok = 1;

    ok &= require_text("pointer input uses one process-wide generation", stack,
                       "staticpthread_mutex_tpointer_input_mutex=PTHREAD_MUTEX_INITIALIZER;"
                       "staticvolatileLONGpointer_input_serial;");
    ok &= require_text("a sample compares its prior generation and continuation kind", final,
                       "previous_serial=InterlockedCompareExchange(&pointer_input_serial,0,0);"
                       "current=si->state==INERTIA_TRACKING&&si->kind==kind&&si->sourceid==sourceid&&"
                       "si->hwnd==hwnd&&si->input_serial==previous_serial;");
    ok &= require_text("an accepted sample advances the generation", final,
                       "input_serial=InterlockedIncrement(&pointer_input_serial);"
                       "pthread_mutex_unlock(&pointer_input_mutex);");
    ok &= require_text("a non-current sample clears old history", safety,
                       "if(!current&&si->state!=INERTIA_IDLE){HWNDold_hwnd=si->hwnd;"
                       "si->state=INERTIA_IDLE;si->count=0;si->pos=0;");
    ok &= require_text("a new sequence stores only its own point", safety,
                       "if(new_sequence)si->anchor=anchor;");
    ok &= require_text("release validates kind source window and generation", final,
                       "current=si->state==INERTIA_TRACKING&&si->kind==kind&&"
                       "si->sourceid==sourceid&&si->hwnd==hwnd&&si->input_serial==input_serial;"
                       "input_serial=InterlockedIncrement(&pointer_input_serial);");
    ok &= require_text("ticks reject a superseded process generation", final,
                       "if(si->input_serial!=InterlockedCompareExchange(&pointer_input_serial,0,0)){"
                       "si->state=INERTIA_IDLE;si->count=0;");
    ok &= require_text("superseded process generations stop their scheduled tracker", stack,
                       "si->state=INERTIA_IDLE;si->count=0;"
                       "inertia_nudge_stop(si->hwnd);return;");
    ok &= require_text("guarded submission rejects a stale generation", safety,
                       "if(*expected_serial!=InterlockedCompareExchange(&pointer_input_serial,0,0))"
                       "{pthread_mutex_unlock(&pointer_input_mutex);returnFALSE;}");
    ok &= require_text("hardware-input status is normalised to Boolean success", safety,
                       "ret=!NtUserSendHardwareInput(hwnd,SEND_HWMSG_RAWINPUT|SEND_HWMSG_FIXED_POSITION|");
    ok &= require_text("vertical coast output carries the saved generation", safety,
                       "send_wheel_at_input(si->hwnd,si->anchor,MOUSEEVENTF_WHEEL,delta,now,"
                       "&si->input_serial,FALSE)");
    ok &= require_text("horizontal coast output carries the saved generation", safety,
                       "send_wheel_at_input(si->hwnd,si->anchor,MOUSEEVENTF_HWHEEL,delta,now,"
                       "&si->input_serial,FALSE)");
    ok &= forbid_text_between("stale output cannot invalidate newer input", safety,
                              "staticBOOLsend_wheel_at_input(", "staticBOOLpointer_button_down(",
                              "InterlockedIncrement(");
    if (ok) pass("new pointer input invalidates older tracking and coast output");
}

static void check_button_serial_and_middle_mode(const char *safety)
{
    int ok = 1;

    ok &= require_text("the driver reports every physical button early", safety,
                       "SERVER_START_REQ(update_driver_button){req->win=wine_server_user_handle(hwnd);"
                       "req->button=button;req->state=pinch_button_is_wheel(button)?-1:down;");
    ok &= require_text_between("every core press is recorded before range handling", safety,
                               "TRACE(\"hwnd%p/%lxbutton%upos%s\\n\"",
                               "if(button>=NB_BUTTONS)returnFALSE;",
                               "notify_button_transition(hwnd,event->button,TRUE);");
    if (count_occurrences(safety, "notify_button_transition(hwnd,event->button,FALSE);") != 3)
    {
        fail("every core release path clears early state",
             "expected unknown-button, middle-drag, and ordinary release notifications");
        ok = 0;
    }
    ok &= require_text("the server accepts early button updates", safety,
                       "DECL_HANDLER(update_driver_button)");
    ok &= require_text("invalid early button reports are rejected", safety,
                       "if(!req->button||req->state<-1||req->state>1){"
                       "set_error(STATUS_INVALID_PARAMETER);return;}");
    ok &= require_text("all physical buttons map to a tracked bucket", safety,
                       "case1:return0;case2:return1;case3:return2;case8:return3;"
                       "case9:return4;default:return5;");
    ok &= require_text("early button counts cannot wrap to released", safety,
                       "if(shared->driver_button_count[bucket]!=0xff)"
                       "shared->driver_button_count[bucket]++;"
                       "elseshared->driver_button_overflow|=1u<<bucket;");
    ok &= require_text("overflowed early state remains held", safety,
                       "elseif(!(shared->driver_button_overflow&(1u<<bucket))&&"
                       "shared->driver_button_count[bucket])shared->driver_button_count[bucket]--;");
    ok &= require_text("every early report advances the serial", safety,
                       "advance_mouse_button_serial(desktop);release_object(desktop);");

    if (count_occurrences(safety, "time,NULL,TRUE);") != 2)
    {
        fail("only two live middle-drag sends request the exception",
             "expected vertical and horizontal middle_drag_motion sends only");
        ok = 0;
    }
    ok &= require_text("vertical live middle drag requests the exception", safety,
                       "send_wheel_at_input(drag->hwnd,drag->origin,MOUSEEVENTF_WHEEL,-delta_y,"
                       "time,NULL,TRUE)");
    ok &= require_text("horizontal live middle drag requests the exception", safety,
                       "send_wheel_at_input(drag->hwnd,drag->origin,MOUSEEVENTF_HWHEEL,delta_x,"
                       "time,NULL,TRUE)");
    ok &= require_text("the helper adds the middle-drag flag only on request", safety,
                       "(middle_drag?SEND_HWMSG_MIDDLE_DRAG:0),&input,0);");
    ok &= require_text("the server derives the narrow middle-drag mode", safety,
                       "boolmiddle_drag=!!(req->flags&SEND_HWMSG_MIDDLE_DRAG);"
                       "unsignedintfixed_position=req->flags&SEND_HWMSG_FIXED_POSITION?"
                       "(middle_drag?HWMSG_FIXED_POSITION_MIDDLE_DRAG:"
                       "HWMSG_FIXED_POSITION_NO_BUTTONS):HWMSG_FIXED_POSITION_NONE;");
    ok &= require_text("invalid middle-drag flag combinations are rejected", safety,
                       "if(middle_drag&&(!(req->flags&SEND_HWMSG_FIXED_POSITION)||force_mk_control||"
                       "origin!=IMO_HARDWARE||req->input.type!=INPUT_MOUSE||"
                       "(req->input.mouse.flags!=MOUSEEVENTF_WHEEL&&"
                       "req->input.mouse.flags!=MOUSEEVENTF_HWHEEL))){"
                       "set_error(STATUS_INVALID_PARAMETER);return;}");
    ok &= require_text("ordinary fixed output requires no early buttons", safety,
                       "if(fixed_position==HWMSG_FIXED_POSITION_NO_BUTTONS)expected_mask=0;");
    ok &= require_text("middle-drag output requires exactly the middle mask", safety,
                       "elseif(fixed_position==HWMSG_FIXED_POSITION_MIDDLE_DRAG)expected_mask=1u<<1;"
                       "elsereturn1;");
    ok &= require_text("server gates require unchanged serial and exact mask", safety,
                       "if(button_serial!=current_serial||desktop_shm->driver_button_mask!=expected_mask)"
                       "return1;");
    ok &= require_text("server gates reject all Win32 button state", safety,
                       "(desktop_shm->keystate[VK_LBUTTON]|desktop_shm->keystate[VK_MBUTTON]|"
                       "desktop_shm->keystate[VK_RBUTTON]|desktop_shm->keystate[VK_XBUTTON1]|"
                       "desktop_shm->keystate[VK_XBUTTON2])&0x80)return1;");
    ok &= require_text("server middle mode requires one non-overflowed Button2", safety,
                       "if(expected_mask&&(desktop_shm->driver_button_count[1]!=1||"
                       "(desktop_shm->driver_button_overflow&expected_mask)))return1;");
    ok &= require_text("client gates require the same exact mask", safety,
                       "stale=desktop_shm->mouse_button_serial!=button_serial||"
                       "desktop_shm->driver_button_mask!=expected_mask||");
    ok &= require_text("client middle mode requires one non-overflowed Button2", safety,
                       "(expected_mask&&(desktop_shm->driver_button_count[1]!=1||"
                       "(desktop_shm->driver_button_overflow&expected_mask)));");
    if (count_occurrences(safety, "fixed_wheel_is_stale(fixed_position,fixed_button_serial)") != 4)
    {
        fail("client delivery rechecks fixed wheel mode after every delay",
             "expected entry, two process-return, and post-hook checks");
        ok = 0;
    }
    if (count_occurrences(safety, "fixed_wheel_is_stale(") < 8)
    {
        fail("server and client both enforce fixed wheel mode",
             "expected definitions plus initial, post-hook, dequeue, and client checks");
        ok = 0;
    }
    ok &= require_text("fixed messages carry their mode and button serial", safety,
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

enum reference_warp_probe
{
    REFERENCE_WARP_AMBIGUOUS,
    REFERENCE_WARP_FAILED,
    REFERENCE_WARP_APPLIED,
};

static double reference_warp_distance(double ax, double ay, double bx, double by)
{
    return fmax(fabs(ax - bx), fabs(ay - by));
}

static enum reference_warp_probe reference_warp_probe(
    double pre_x, double pre_y, double target_x, double target_y,
    double raw_x, double raw_y, double cooked_x, double cooked_y,
    int raw_seen, unsigned int raw_time, unsigned int cooked_time)
{
    double span = reference_warp_distance(pre_x, pre_y, target_x, target_y);
    double failed_x, failed_y, applied_x, applied_y;
    double failed_error, applied_error, tolerance;

    if (span < 8.0 || !raw_seen || raw_time != cooked_time) return REFERENCE_WARP_AMBIGUOUS;
    failed_x = pre_x + round(raw_x);
    failed_y = pre_y + round(raw_y);
    applied_x = target_x + round(raw_x);
    applied_y = target_y + round(raw_y);
    failed_error = reference_warp_distance(cooked_x, cooked_y, failed_x, failed_y);
    applied_error = reference_warp_distance(cooked_x, cooked_y, applied_x, applied_y);
    tolerance = fmin(8.0, fmax(2.0, span / 8.0));
    if (failed_error <= tolerance && applied_error >= failed_error + span / 2.0)
        return REFERENCE_WARP_FAILED;
    if (applied_error <= tolerance && failed_error >= applied_error + span / 2.0)
        return REFERENCE_WARP_APPLIED;
    return REFERENCE_WARP_AMBIGUOUS;
}

static int reference_ignore_synthetic(
    double target_x, double target_y, double cooked_x, double cooked_y,
    int *pending)
{
    if (!*pending) return 0;
    if (cooked_x == target_x && cooked_y == target_y) return 1;
    *pending = 0;
    return 0;
}

static void check_warp_probe_math(void)
{
    unsigned int votes = 0;
    enum reference_warp_probe probe;
    int synthetic_pending = 1;
    double mapped;

    probe = reference_warp_probe(100, 20, 50, 20, 5, 0, 105, 20, 1, 10, 10);
    mapped = 50 + 105 - 100;
    if (probe != REFERENCE_WARP_FAILED || mapped != 55)
        fail("a failed warp preserves its first physical delta",
             "the first cooked motion was lost or classified incorrectly");
    else
        pass("a failed warp preserves its first physical delta");

    /* At steady velocity a server-applied cooked point can equal the old
     * pre-warp point. Coordinate proximity alone misclassifies this case;
     * the shared raw delta identifies target + delta correctly. */
    probe = reference_warp_probe(60, 20, 50, 20, 10, 0, 60, 20, 1, 11, 11);
    if (probe != REFERENCE_WARP_APPLIED)
        fail("server-handled steady motion is not double-emulated",
             "raw/cooked correlation did not identify target plus delta");
    else
        pass("server-handled steady motion is not double-emulated");

    if (!reference_ignore_synthetic(50, 20, 50, 20, &synthetic_pending) ||
        !reference_ignore_synthetic(50, 20, 50, 20, &synthetic_pending) ||
        reference_ignore_synthetic(50, 20, 51, 20, &synthetic_pending) || synthetic_pending ||
        reference_ignore_synthetic(50, 20, 50, 20, &synthetic_pending))
        fail("cross-thread synthetic warps are isolated", "copies survived or filtering stayed armed");
    else
        pass("cross-thread synthetic warps are isolated");

    if (reference_warp_probe(100, 20, 50, 20, 5, 0, 105, 20, 0, 12, 12) !=
            REFERENCE_WARP_AMBIGUOUS ||
        reference_warp_probe(100, 20, 50, 20, 5, 0, 105, 20, 1, 12, 13) !=
            REFERENCE_WARP_AMBIGUOUS ||
        reference_warp_probe(55, 20, 50, 20, 5, 0, 60, 20, 1, 14, 14) !=
            REFERENCE_WARP_AMBIGUOUS)
        fail("incomplete warp evidence stays native", "an unavailable correlation activated emulation");
    else
        pass("incomplete warp evidence stays native");

    probe = reference_warp_probe(100, 20, 50, 20, 5, 0, 105, 20, 1, 15, 15);
    if (probe == REFERENCE_WARP_FAILED) votes++;
    if (votes >= 2)
        fail("one failed correlation cannot activate automatic emulation", "hysteresis was bypassed");
    else
        pass("one failed correlation cannot activate automatic emulation");
    if (probe == REFERENCE_WARP_FAILED) votes++;
    if (votes != 2)
        fail("two failed correlations activate automatic emulation", "failure votes did not converge");
    else
        pass("two failed correlations activate automatic emulation");
}

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

enum reference_wheel_route
{
    REFERENCE_WHEEL_FIXED,
    REFERENCE_WHEEL_STOCK,
    REFERENCE_WHEEL_SUPPRESSED,
};

static enum reference_wheel_route reference_wheel_route(
    int enabled, unsigned int event_mask, unsigned int held_mask, int middle_drag)
{
    if (enabled && event_mask && event_mask == held_mask && !middle_drag)
        return REFERENCE_WHEEL_STOCK;
    if (event_mask || held_mask || middle_drag) return REFERENCE_WHEEL_SUPPRESSED;
    return REFERENCE_WHEEL_FIXED;
}

static void check_held_wheel_provenance(void)
{
    unsigned int i;
    int ok = 1;

    for (i = 0; i < 5; i++)
        if (reference_wheel_route(1, 1u << i, 1u << i, 0) != REFERENCE_WHEEL_STOCK)
            ok = 0;
    if (reference_wheel_route(1, 5u, 5u, 0) != REFERENCE_WHEEL_STOCK ||
        reference_wheel_route(1, 1u, 2u, 0) != REFERENCE_WHEEL_SUPPRESSED ||
        reference_wheel_route(1, 1u, 0u, 0) != REFERENCE_WHEEL_SUPPRESSED ||
        reference_wheel_route(1, 0u, 1u, 0) != REFERENCE_WHEEL_SUPPRESSED ||
        reference_wheel_route(0, 1u, 1u, 0) != REFERENCE_WHEEL_SUPPRESSED ||
        reference_wheel_route(1, 2u, 2u, 1) != REFERENCE_WHEEL_SUPPRESSED ||
        reference_wheel_route(1, 0u, 0u, 0) != REFERENCE_WHEEL_FIXED)
        ok = 0;
    if (!ok)
        fail("held-wheel routing requires exact physical provenance",
             "an unstable, disabled, or middle-drag case reached stock delivery");
    else
        pass("held-wheel routing requires exact physical provenance");
}

static int reference_legacy_copy_suppress(
    int valid, unsigned int tag_time, unsigned int event_time,
    unsigned long tag_window, unsigned long event_window,
    unsigned int wheel_buttons, unsigned int tag_held, unsigned int event_held,
    unsigned int button, int send_event)
{
    unsigned int button_bit;

    if (!valid || event_time != tag_time) return 0;
    button_bit = button <= 7 ? 1u << button : 0;
    return !send_event && event_window == tag_window &&
           (wheel_buttons & button_bit) && event_held && event_held == tag_held;
}

static void check_legacy_wheel_copy_model(void)
{
    const unsigned int vertical_up = 1u << 4;
    const unsigned int horizontal_left = 1u << 6;
    const unsigned int held = 1u << 0;
    int ok = 1;

    /* Direction bits deliberately survive repeated generated notches carrying
     * the same X timestamp. All other identity fields remain exact. */
    if (!reference_legacy_copy_suppress(1, 100, 100, 9, 9, vertical_up, held, held, 4, 0) ||
        !reference_legacy_copy_suppress(1, 100, 100, 9, 9, vertical_up, held, held, 4, 0) ||
        !reference_legacy_copy_suppress(1, 100, 100, 9, 9, horizontal_left, held, held, 6, 0) ||
        reference_legacy_copy_suppress(0, 100, 100, 9, 9, vertical_up, held, held, 4, 0) ||
        reference_legacy_copy_suppress(1, 100, 101, 9, 9, vertical_up, held, held, 4, 0) ||
        reference_legacy_copy_suppress(1, 100, 100, 9, 10, vertical_up, held, held, 4, 0) ||
        reference_legacy_copy_suppress(1, 100, 100, 9, 9, vertical_up, held, held, 5, 0) ||
        reference_legacy_copy_suppress(1, 100, 100, 9, 9, vertical_up, held, 2u, 4, 0) ||
        reference_legacy_copy_suppress(1, 100, 100, 9, 9, vertical_up, held, 0u, 4, 0) ||
        reference_legacy_copy_suppress(1, 100, 100, 9, 9, vertical_up, held, held, 4, 1) ||
        reference_legacy_copy_suppress(1, 100, 100, 9, 9, vertical_up, held, held, 8, 0))
        ok = 0;
    if (!ok)
        fail("legacy wheel-copy model admits only an exact generated event",
             "time, window, direction, held mask, or send_event isolation failed");
    else
        pass("legacy wheel-copy model admits only an exact generated event");
}

enum reference_touchpad_inertia_mode
{
    REFERENCE_TOUCHPAD_INERTIA_DISABLED,
    REFERENCE_TOUCHPAD_INERTIA_AUTO,
    REFERENCE_TOUCHPAD_INERTIA_ENABLED,
};

enum reference_middle_throw_mode
{
    REFERENCE_MIDDLE_THROW_DISABLED,
    REFERENCE_MIDDLE_THROW_ENABLED,
};

static int reference_continuation_enabled(
    int middle_drag, enum reference_touchpad_inertia_mode touchpad,
    enum reference_middle_throw_mode middle_throw)
{
    if (middle_drag) return middle_throw == REFERENCE_MIDDLE_THROW_ENABLED;
    return touchpad == REFERENCE_TOUCHPAD_INERTIA_ENABLED;
}

static void check_default_continuation_matrix(void)
{
    const enum reference_touchpad_inertia_mode default_touchpad =
        REFERENCE_TOUCHPAD_INERTIA_ENABLED;
    const enum reference_middle_throw_mode default_middle =
        REFERENCE_MIDDLE_THROW_ENABLED;

    if (!reference_continuation_enabled(0, default_touchpad, default_middle) ||
        !reference_continuation_enabled(1, default_touchpad, default_middle) ||
        reference_continuation_enabled(0, REFERENCE_TOUCHPAD_INERTIA_AUTO, default_middle) ||
        reference_continuation_enabled(0, REFERENCE_TOUCHPAD_INERTIA_DISABLED, default_middle) ||
        reference_continuation_enabled(1, default_touchpad, REFERENCE_MIDDLE_THROW_DISABLED) ||
        !reference_continuation_enabled(0, REFERENCE_TOUCHPAD_INERTIA_ENABLED,
                                        REFERENCE_MIDDLE_THROW_DISABLED) ||
        !reference_continuation_enabled(1, REFERENCE_TOUCHPAD_INERTIA_DISABLED,
                                        REFERENCE_MIDDLE_THROW_ENABLED))
        fail("default continuation matrix enables both independent sources",
             "a default was disabled, auto became active, or source controls were coupled");
    else
        pass("default continuation matrix enables fine inertia and middle throw; auto stays inert");
}

struct coast_result
{
    struct safe_axis axes[2];
    unsigned int messages;
    unsigned int elapsed_ms;
    unsigned int maximum_packet;
    int stopped_by_speed;
    int stopped_by_travel;
    int stopped_by_messages;
};

static struct coast_result run_reference_coast(double vx, double vy, double rate)
{
    struct coast_result result = {{{vx, 0.0, 0}, {vy, 0.0, 0}}, 0, 0, 0, 0, 0, 0};
    unsigned int i, axis;

    for (i = 0; i < 1000; i++)
    {
        if (hypot(result.axes[0].velocity, result.axes[1].velocity) < 60.0)
        {
            result.stopped_by_speed = 1;
            break;
        }
        if (result.messages >= MAX_MESSAGES_VALUE)
        {
            result.stopped_by_messages = 1;
            break;
        }
        if (result.axes[0].travel >= MAX_TRAVEL_VALUE &&
            result.axes[1].travel >= MAX_TRAVEL_VALUE)
        {
            result.stopped_by_travel = 1;
            break;
        }

        result.elapsed_ms += 8;
        for (axis = 0; axis < 2 && result.messages < MAX_MESSAGES_VALUE; axis++)
        {
            int packet = safe_axis_tick(&result.axes[axis], 8, rate);
            unsigned int magnitude = (unsigned int)abs(packet);

            if (!packet) continue;
            if (magnitude > result.maximum_packet) result.maximum_packet = magnitude;
            result.messages++;
        }
    }
    if (result.messages >= MAX_MESSAGES_VALUE) result.stopped_by_messages = 1;
    if (result.axes[0].travel >= MAX_TRAVEL_VALUE &&
        result.axes[1].travel >= MAX_TRAVEL_VALUE)
        result.stopped_by_travel = 1;
    return result;
}

static int coast_within_envelope(const struct coast_result *result)
{
    return result->maximum_packet <= MAX_PACKET_VALUE &&
           result->axes[0].travel <= MAX_TRAVEL_VALUE &&
           result->axes[1].travel <= MAX_TRAVEL_VALUE &&
           result->axes[0].travel + result->axes[1].travel <= MAX_TOTAL_VALUE &&
           result->messages <= MAX_MESSAGES_VALUE && result->elapsed_ms <= 4000;
}

static void check_math_envelope(void)
{
    const double diagonal = MAX_SPEED_VALUE / sqrt(2.0);
    struct safe_axis normal = {MAX_SPEED_VALUE, 0.0, 0};
    struct safe_axis stalled = {MAX_SPEED_VALUE, 0.0, 0};
    struct safe_axis overflow = {1000000000.0, 0.0, 0};
    struct safe_axis reverse = {-1000000000.0, 0.0, 0};
    struct coast_result default_single, default_diagonal, slow_diagonal, packet_limited;
    double expected_velocity, expected_normal;
    int packet, next;

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

    default_single = run_reference_coast(MAX_SPEED_VALUE, 0.0, 4.0);
    default_diagonal = run_reference_coast(diagonal, diagonal, 4.0);
    if (!coast_within_envelope(&default_single) || !default_single.stopped_by_speed ||
        default_single.stopped_by_messages || default_single.stopped_by_travel ||
        !coast_within_envelope(&default_diagonal) || !default_diagonal.stopped_by_speed ||
        default_diagonal.stopped_by_messages || default_diagonal.stopped_by_travel)
        fail("the default exponential coast reaches its natural stop",
             "the default curve hit a safety backstop or escaped the envelope");
    else
        pass("the default single-axis and diagonal coasts reach a bounded natural stop");

    slow_diagonal = run_reference_coast(diagonal, diagonal, 0.5);
    if (!coast_within_envelope(&slow_diagonal) || !slow_diagonal.stopped_by_travel ||
        slow_diagonal.axes[0].travel != MAX_TRAVEL_VALUE ||
        slow_diagonal.axes[1].travel != MAX_TRAVEL_VALUE)
        fail("slow custom curves stop at four notches per axis",
             "the independent travel cap was not reached safely");
    else
        pass("slow custom curves stop at four notches per axis");

    packet_limited = run_reference_coast(diagonal, diagonal, 1.67);
    if (!coast_within_envelope(&packet_limited) || !packet_limited.stopped_by_messages ||
        packet_limited.messages != MAX_MESSAGES_VALUE)
        fail("the 192-message budget independently bounds custom curves",
             "the reference curve did not terminate at the packet backstop");
    else
        pass("the 192-message budget independently bounds custom curves");
}

int main(int argc, char **argv)
{
    static const char *const defaults[] =
    {
        "patches/0090-winex11-preserve-precision-scrolling-from-XInput2-scroll-.patch",
        "patches/0091-winex11-coast-scrolling-and-thrown-middle-drags-after-rel.patch",
        "patches/0074-winex11-server-report-a-touchpad-pinch-as-Ctrl-tagged-whe.patch",
        "patches/0072-winex11-registry-pointer-settings-and-middle-button-dra.patch",
        "patches/0092-winex11-bound-and-isolate-pointer-gesture-output.patch",
        "patches/0093-winex11-release-stale-cursor-clipping-state-when-X-f.patch",
        "patches/0094-winex11-emulate-only-observed-failed-pointer-warps-o.patch",
        "patches/0095-winex11-separate-pointer-coast-sources.patch"
    };
    struct text stack_source = {0}, safety_source = {0}, warp_source = {0}, final_source = {0};
    const char *paths[8];
    char *stack, *safety, *warp, *final;
    int i;

    if (argc != 1 && argc != 9)
    {
        fprintf(stderr, "usage: %s [0090 0091 0074 0072 0092 0093 0094 0095]\n", argv[0]);
        return 2;
    }
    for (i = 0; i < 8; i++) paths[i] = argc == 9 ? argv[i + 1] : defaults[i];
    for (i = 0; i < 8; i++)
        if (!read_patch_new_side(paths[i], &stack_source)) return 2;
    if (!read_patch_new_side(paths[4], &safety_source)) return 2;
    if (!read_patch_new_side(paths[6], &warp_source)) return 2;
    if (!read_patch_new_side(paths[7], &final_source)) return 2;

    stack = compact(stack_source.data ? stack_source.data : "");
    safety = compact(safety_source.data ? safety_source.data : "");
    warp = compact(warp_source.data ? warp_source.data : "");
    final = compact(final_source.data ? final_source.data : "");
    if (!stack || !safety || !warp || !final)
    {
        fprintf(stderr, "FAIL: out of memory while compacting patch sources\n");
        free(stack_source.data);
        free(safety_source.data);
        free(warp_source.data);
        free(final_source.data);
        free(stack);
        free(safety);
        free(warp);
        free(final);
        return 2;
    }

    check_pointer_setting_fallback(stack, safety, final);
    check_warp_emulation(stack, warp);
    check_held_and_direct_input(stack, safety, final);
    check_legacy_wheel_copy_guard(final);
    check_direct_packet_bounds(stack, safety, final);
    check_continuation_sources(final);
    check_inertia_timer_initialization(final);
    check_one_shot_inertia_ticks(final);
    check_inertia_lifecycle_cancellation(final);
    check_accumulator_routing(safety);
    check_inertia_limits(stack, safety, final);
    check_inertia_generation(stack, safety, final);
    check_button_serial_and_middle_mode(safety);
    check_held_wheel_provenance();
    check_legacy_wheel_copy_model();
    check_default_continuation_matrix();
    check_warp_probe_math();
    check_math_envelope();

    free(stack_source.data);
    free(safety_source.data);
    free(warp_source.data);
    free(final_source.data);
    free(stack);
    free(safety);
    free(warp);
    free(final);
    if (failures)
    {
        fprintf(stderr, "pointer safety checks: %u failure%s\n",
                failures, failures == 1 ? "" : "s");
        return 1;
    }
    puts("pointer safety checks: PASS");
    return 0;
}
