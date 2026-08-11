/* Check that both mouse-wheel messages keep screen coordinates and that hit
 * testing never derives a non-client WM_MOUSEHWHEEL message. Run this probe
 * in a graphical Wine session. It focuses a popup, moves the pointer, then
 * restores the old pointer position. Exit status 0 means pass, 1 means a
 * check failed, and 2 means setup failed. */

#include <windows.h>
#include <windowsx.h>
#include <stdio.h>

static BOOL force_caption_hittest;

static LRESULT CALLBACK window_proc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam)
{
    if (message == WM_NCHITTEST && force_caption_hittest) return HTCAPTION;
    return DefWindowProcA(hwnd, message, wparam, lparam);
}

static void drain_messages(void)
{
    MSG message;

    while (PeekMessageA(&message, NULL, 0, 0, PM_REMOVE))
    {
        TranslateMessage(&message);
        DispatchMessageA(&message);
    }
}

static BOOL inject_wheel(DWORD flags)
{
    INPUT input = {0};

    input.type = INPUT_MOUSE;
    input.mi.mouseData = WHEEL_DELTA;
    input.mi.dwFlags = flags;
    return SendInput(1, &input, sizeof(input)) == 1;
}

static BOOL wait_for_message(HWND hwnd, UINT first, UINT last, MSG *message)
{
    unsigned int i;

    for (i = 0; i < 100; ++i)
    {
        if (PeekMessageA(message, hwnd, first, last, PM_REMOVE)) return TRUE;
        Sleep(1);
    }
    return FALSE;
}

static BOOL check_wheel_coordinates(HWND hwnd, DWORD flags, UINT expected_message, const char *name)
{
    POINT cursor;
    MSG message;
    int x, y;

    if (!GetCursorPos(&cursor))
    {
        fprintf(stderr, "FAIL: GetCursorPos failed for %s: error %lu\n",
                name, (unsigned long)GetLastError());
        return FALSE;
    }
    if (!inject_wheel(flags))
    {
        fprintf(stderr, "FAIL: SendInput failed for %s: error %lu\n",
                name, (unsigned long)GetLastError());
        return FALSE;
    }
    if (!wait_for_message(hwnd, expected_message, expected_message, &message))
    {
        fprintf(stderr, "FAIL: timed out waiting for %s\n", name);
        return FALSE;
    }

    x = GET_X_LPARAM(message.lParam);
    y = GET_Y_LPARAM(message.lParam);
    printf("CHECK: %s cursor=(%ld,%ld) lParam=(%d,%d)\n",
           name, (long)cursor.x, (long)cursor.y, x, y);
    if (x == cursor.x && y == cursor.y) return TRUE;

    fprintf(stderr, "FAIL: %s has lParam=(%d,%d), expected screen point (%ld,%ld)\n",
            name, x, y, (long)cursor.x, (long)cursor.y);
    return FALSE;
}

int main(void)
{
    const UINT derived_nc_hwheel = WM_MOUSEHWHEEL + WM_NCMOUSEMOVE - WM_MOUSEMOVE;
    WNDCLASSA class = {0};
    HWND hwnd;
    POINT cursor, old_cursor;
    MSG message;
    BOOL passed = TRUE;
    int window_x, window_y;

    class.lpfnWndProc = window_proc;
    class.hInstance = GetModuleHandleA(NULL);
    class.lpszClassName = "wheel-coordinate-probe";
    if (!RegisterClassA(&class))
    {
        fprintf(stderr, "FAIL: RegisterClassA failed: error %lu\n",
                (unsigned long)GetLastError());
        return 2;
    }

    window_x = GetSystemMetrics(SM_CXSCREEN) / 4;
    window_y = GetSystemMetrics(SM_CYSCREEN) / 4;
    cursor.x = window_x + 40;
    cursor.y = window_y + 40;
    hwnd = CreateWindowExA(0, class.lpszClassName, "wheel coordinates", WS_POPUP | WS_VISIBLE,
                           window_x, window_y, 160, 120, NULL, NULL, class.hInstance, NULL);
    if (!hwnd)
    {
        fprintf(stderr, "FAIL: CreateWindowExA failed: error %lu\n",
                (unsigned long)GetLastError());
        return 2;
    }

    if (!GetCursorPos(&old_cursor))
    {
        fprintf(stderr, "FAIL: GetCursorPos failed before probe: error %lu\n",
                (unsigned long)GetLastError());
        DestroyWindow(hwnd);
        return 2;
    }
    SetForegroundWindow(hwnd);
    if (!SetCursorPos(cursor.x, cursor.y))
    {
        fprintf(stderr, "FAIL: SetCursorPos failed before probe: error %lu\n",
                (unsigned long)GetLastError());
        DestroyWindow(hwnd);
        return 2;
    }
    Sleep(20);
    drain_messages();

    passed &= check_wheel_coordinates(hwnd, MOUSEEVENTF_WHEEL, WM_MOUSEWHEEL, "WM_MOUSEWHEEL");
    passed &= check_wheel_coordinates(hwnd, MOUSEEVENTF_HWHEEL, WM_MOUSEHWHEEL, "WM_MOUSEHWHEEL");

    force_caption_hittest = TRUE;
    if (!SetCursorPos(cursor.x, cursor.y))
    {
        fprintf(stderr, "FAIL: SetCursorPos failed before HTCAPTION case: error %lu\n",
                (unsigned long)GetLastError());
        passed = FALSE;
    }
    Sleep(20);
    drain_messages();
    if (!inject_wheel(MOUSEEVENTF_HWHEEL))
    {
        fprintf(stderr, "FAIL: SendInput failed for WM_MOUSEHWHEEL over HTCAPTION: error %lu\n",
                (unsigned long)GetLastError());
        passed = FALSE;
    }
    else
    {
        /* 0x00ae is the invalid code old Wine predicted by applying the
         * non-client mouse offset to WM_MOUSEHWHEEL. */
        if (wait_for_message(hwnd, derived_nc_hwheel, derived_nc_hwheel, &message))
        {
            fprintf(stderr, "FAIL: PeekMessageA returned derived non-client message %#x\n",
                    message.message);
            passed = FALSE;
        }
        if (!wait_for_message(hwnd, WM_MOUSEHWHEEL, WM_MOUSEHWHEEL, &message))
        {
            fprintf(stderr, "FAIL: timed out waiting for WM_MOUSEHWHEEL after HTCAPTION\n");
            passed = FALSE;
        }
        else if (GET_X_LPARAM(message.lParam) != cursor.x ||
                 GET_Y_LPARAM(message.lParam) != cursor.y)
        {
            fprintf(stderr,
                    "FAIL: WM_MOUSEHWHEEL after HTCAPTION has lParam=(%d,%d), "
                    "expected screen point (%ld,%ld)\n",
                    GET_X_LPARAM(message.lParam), GET_Y_LPARAM(message.lParam),
                    (long)cursor.x, (long)cursor.y);
            passed = FALSE;
        }
    }

    if (!SetCursorPos(old_cursor.x, old_cursor.y))
    {
        fprintf(stderr, "FAIL: SetCursorPos failed while restoring pointer: error %lu\n",
                (unsigned long)GetLastError());
        passed = FALSE;
    }
    DestroyWindow(hwnd);
    printf("%s\n", passed ? "PASS" : "FAIL");
    return passed ? 0 : 1;
}
