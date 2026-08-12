/* heldwheel.c - receive physical wheel input in a capture-owning Wine window.
 *
 * Pair this with the Linux-side uclick tool.  This process never synthesizes
 * input: it records the Win32 packet produced after the kernel, compositor,
 * XWayland, and winex11 paths have handled a real uinput mouse event.
 *
 * build: winegcc -O2 -Wall -Wextra -Werror -o heldwheel.exe heldwheel.c
 */

#include <windows.h>
#include <windowsx.h>
#include <stdio.h>

static unsigned int held_buttons;
static unsigned long sequence;

static const char *message_name( UINT message )
{
    switch (message)
    {
        case WM_LBUTTONDOWN: return "WM_LBUTTONDOWN";
        case WM_LBUTTONUP: return "WM_LBUTTONUP";
        case WM_MBUTTONDOWN: return "WM_MBUTTONDOWN";
        case WM_MBUTTONUP: return "WM_MBUTTONUP";
        case WM_RBUTTONDOWN: return "WM_RBUTTONDOWN";
        case WM_RBUTTONUP: return "WM_RBUTTONUP";
        case WM_MOUSEWHEEL: return "WM_MOUSEWHEEL";
        case WM_MOUSEHWHEEL: return "WM_MOUSEHWHEEL";
        default: return "unknown";
    }
}

static unsigned int button_mask( UINT message )
{
    switch (message)
    {
        case WM_LBUTTONDOWN:
        case WM_LBUTTONUP:
            return MK_LBUTTON;
        case WM_MBUTTONDOWN:
        case WM_MBUTTONUP:
            return MK_MBUTTON;
        case WM_RBUTTONDOWN:
        case WM_RBUTTONUP:
            return MK_RBUTTON;
        default:
            return 0;
    }
}

static void print_key_state( unsigned int keys )
{
    printf( " keys=0x%04x L=%u M=%u R=%u shift=%u ctrl=%u X1=%u X2=%u",
            keys, !!(keys & MK_LBUTTON), !!(keys & MK_MBUTTON),
            !!(keys & MK_RBUTTON), !!(keys & MK_SHIFT),
            !!(keys & MK_CONTROL), !!(keys & MK_XBUTTON1),
            !!(keys & MK_XBUTTON2) );
}

static void log_button( HWND target, UINT message, WPARAM wparam, LPARAM lparam )
{
    POINT point = {GET_X_LPARAM( lparam ), GET_Y_LPARAM( lparam )};

    ClientToScreen( target, &point );
    printf( "%06lu button=%s wParam=0x%llx", ++sequence,
            message_name( message ), (unsigned long long)(UINT_PTR)wparam );
    print_key_state( GET_KEYSTATE_WPARAM( wparam ) );
    printf( " target=%p capture=%p point_screen=(%ld,%ld)\n", (void *)target,
            (void *)GetCapture(), (long)point.x, (long)point.y );
    fflush( stdout );
}

static void log_wheel( HWND target, UINT message, WPARAM wparam, LPARAM lparam )
{
    POINT point = {GET_X_LPARAM( lparam ), GET_Y_LPARAM( lparam )};
    HWND capture = GetCapture();
    HWND hit = WindowFromPoint( point );

    printf( "%06lu wheel=%s delta=%d wParam=0x%llx", ++sequence,
            message_name( message ), GET_WHEEL_DELTA_WPARAM( wparam ),
            (unsigned long long)(UINT_PTR)wparam );
    print_key_state( GET_KEYSTATE_WPARAM( wparam ) );
    printf( " target=%p capture=%p point_screen=(%ld,%ld) hit=%p\n",
            (void *)target, (void *)capture, (long)point.x, (long)point.y,
            (void *)hit );
    fflush( stdout );
}

static LRESULT CALLBACK window_proc( HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam )
{
    unsigned int mask = button_mask( message );

    switch (message)
    {
        case WM_LBUTTONDOWN:
        case WM_MBUTTONDOWN:
        case WM_RBUTTONDOWN:
            held_buttons |= mask;
            SetCapture( hwnd );
            log_button( hwnd, message, wparam, lparam );
            return 0;

        case WM_LBUTTONUP:
        case WM_MBUTTONUP:
        case WM_RBUTTONUP:
            log_button( hwnd, message, wparam, lparam );
            held_buttons &= ~mask;
            if (!held_buttons && GetCapture() == hwnd) ReleaseCapture();
            return 0;

        case WM_MOUSEWHEEL:
        case WM_MOUSEHWHEEL:
            log_wheel( hwnd, message, wparam, lparam );
            return 0;

        case WM_CAPTURECHANGED:
            printf( "%06lu event=WM_CAPTURECHANGED target=%p capture=%p new_capture=%p\n",
                    ++sequence, (void *)hwnd, (void *)GetCapture(), (void *)(HWND)lparam );
            fflush( stdout );
            return 0;

        case WM_KEYDOWN:
            if (wparam == VK_ESCAPE)
            {
                DestroyWindow( hwnd );
                return 0;
            }
            break;

        case WM_DESTROY:
            if (GetCapture() == hwnd) ReleaseCapture();
            PostQuitMessage( 0 );
            return 0;
    }
    return DefWindowProcA( hwnd, message, wparam, lparam );
}

int main( void )
{
    HINSTANCE instance = GetModuleHandleA( NULL );
    const char class_name[] = "held-wheel-receiver";
    WNDCLASSA window_class = {0};
    int screen_width = GetSystemMetrics( SM_CXSCREEN );
    int screen_height = GetSystemMetrics( SM_CYSCREEN );
    HWND window;
    MSG message;
    BOOL result;

    window_class.lpfnWndProc = window_proc;
    window_class.hInstance = instance;
    window_class.hCursor = LoadCursorA( NULL, IDC_ARROW );
    window_class.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
    window_class.lpszClassName = class_name;
    if (!RegisterClassA( &window_class ))
    {
        fprintf( stderr, "RegisterClass failed: error %lu\n",
                 (unsigned long)GetLastError() );
        return 2;
    }

    window = CreateWindowExA( 0, class_name,
                              "Held-wheel receiver - keep the pointer in this window",
                              WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                              (screen_width - 640) / 2, (screen_height - 260) / 2,
                              640, 260, NULL, NULL, instance, NULL );
    if (!window)
    {
        fprintf( stderr, "CreateWindow failed: error %lu\n",
                 (unsigned long)GetLastError() );
        return 2;
    }

    ShowWindow( window, SW_SHOW );
    UpdateWindow( window );
    SetForegroundWindow( window );
    SetFocus( window );
    printf( "READY target=%p pid=%lu; mouse down captures the window; Escape exits\n",
            (void *)window, (unsigned long)GetCurrentProcessId() );
    fflush( stdout );

    while ((result = GetMessageA( &message, NULL, 0, 0 )) > 0)
    {
        TranslateMessage( &message );
        DispatchMessageA( &message );
    }
    if (result == -1)
    {
        fprintf( stderr, "GetMessage failed: error %lu\n",
                 (unsigned long)GetLastError() );
        return 2;
    }
    return 0;
}
