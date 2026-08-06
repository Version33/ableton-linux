/* Repro for the Alt+number menu-bar activation divergence (Mike Verdone,
 * 2026-08-06). A window whose wndproc swallows WM_SYSKEYDOWN/WM_SYSCHAR for
 * Alt+4 -- the way Live handles its "Move Focus to the Device View"
 * shortcut -- then watches what DefWindowProc does when Alt is released.
 *
 * Modes:
 *   swallow  - handle Alt+4 like Live does (return 0, no DefWindowProc)
 *   pass     - pass everything to DefWindowProc (app with no Alt+4 binding)
 *
 * Expected on real Windows (both modes): no menu-loop entry from a chorded
 * Alt press. Win32k tracks "another key was pressed while Alt was down" in
 * the input queue (QF_FMENUSTATUSBREAK), independent of what the app does
 * with the messages.
 *
 * Under Wine, defwnd.c tracks that state in a static (menu_sys_key) updated
 * only when messages reach DefWindowProc, so swallow mode leaves it armed.
 */

#include <windows.h>
#include <stdio.h>

static int swallow_mode;
static DWORD t0;

static void say( const char *fmt, ... )
{
    va_list ap;
    va_start( ap, fmt );
    printf( "[%5lu] ", GetTickCount() - t0 );
    vprintf( fmt, ap );
    printf( "\n" );
    fflush( stdout );
    va_end( ap );
}

static LRESULT CALLBACK wndproc( HWND hwnd, UINT msg, WPARAM wp, LPARAM lp )
{
    switch (msg)
    {
    case WM_SYSKEYDOWN:
        say( "WM_SYSKEYDOWN wp=%02x alt=%d", (UINT)wp, (lp & (1 << 29)) != 0 );
        if (swallow_mode && wp == '4') { say( "  -> swallowed (app handled Alt+4)" ); return 0; }
        break;
    case WM_SYSKEYUP:
        say( "WM_SYSKEYUP   wp=%02x", (UINT)wp );
        if (swallow_mode && wp == '4') { say( "  -> swallowed" ); return 0; }
        break;
    case WM_KEYDOWN:
        say( "WM_KEYDOWN    wp=%02x", (UINT)wp );
        break;
    case WM_KEYUP:
        say( "WM_KEYUP      wp=%02x", (UINT)wp );
        break;
    case WM_SYSCHAR:
        say( "WM_SYSCHAR    wp=%02x ('%c')", (UINT)wp, (char)wp );
        if (swallow_mode && wp == '4') { say( "  -> swallowed" ); return 0; }
        break;
    case WM_SYSCOMMAND:
        if ((wp & 0xfff0) == SC_KEYMENU)
            say( "WM_SYSCOMMAND SC_KEYMENU ch=%02lx  <=== menu-bar activation", (ULONG_PTR)lp );
        break;
    case WM_ENTERMENULOOP:
        say( "WM_ENTERMENULOOP  <=== menu mode entered" );
        break;
    case WM_EXITMENULOOP:
        say( "WM_EXITMENULOOP" );
        break;
    case WM_INITMENUPOPUP:
        say( "WM_INITMENUPOPUP  <=== a dropdown opened" );
        break;
    case WM_DESTROY:
        PostQuitMessage( 0 );
        return 0;
    }
    return DefWindowProcA( hwnd, msg, wp, lp );
}

static void key( WORD vk, DWORD flags )
{
    INPUT in = { .type = INPUT_KEYBOARD };
    in.ki.wVk = vk;
    in.ki.wScan = MapVirtualKeyA( vk, MAPVK_VK_TO_VSC );
    in.ki.dwFlags = flags;
    SendInput( 1, &in, sizeof(in) );
    Sleep( 30 );
}

static DWORD WINAPI inject( void *arg )
{
    HWND hwnd = arg;
    int i;

    Sleep( 400 );
    for (i = 0; i < 50 && GetForegroundWindow() != hwnd; i++)
    {
        SetForegroundWindow( hwnd );
        Sleep( 100 );
    }
    say( "foreground=%d (want 1)", GetForegroundWindow() == hwnd );
    say( "--- inject: Alt down, 4 down, 4 up, Alt up (typing-order release)" );
    key( VK_MENU, 0 );
    key( '4', 0 );
    key( '4', KEYEVENTF_KEYUP );
    key( VK_MENU, KEYEVENTF_KEYUP );

    Sleep( 600 );
    say( "--- inject: press F (does a menu open?)" );
    key( 'F', 0 );
    key( 'F', KEYEVENTF_KEYUP );

    Sleep( 600 );
    say( "--- inject: Esc, Esc (leave any menu mode)" );
    key( VK_ESCAPE, 0 );
    key( VK_ESCAPE, KEYEVENTF_KEYUP );
    key( VK_ESCAPE, 0 );
    key( VK_ESCAPE, KEYEVENTF_KEYUP );

    Sleep( 400 );
    say( "--- inject: Alt down, 4 down, Alt up, 4 up (alt-first release)" );
    key( VK_MENU, 0 );
    key( '4', 0 );
    key( VK_MENU, KEYEVENTF_KEYUP );
    key( '4', KEYEVENTF_KEYUP );

    Sleep( 600 );
    say( "--- inject: press F again" );
    key( 'F', 0 );
    key( 'F', KEYEVENTF_KEYUP );

    Sleep( 600 );
    key( VK_ESCAPE, 0 );
    key( VK_ESCAPE, KEYEVENTF_KEYUP );
    Sleep( 200 );
    PostMessageA( hwnd, WM_CLOSE, 0, 0 );
    return 0;
}

int main( int argc, char **argv )
{
    WNDCLASSA wc = { .lpfnWndProc = wndproc, .lpszClassName = "altnum_test" };
    HMENU bar = CreateMenu(), file = CreatePopupMenu(), edit = CreatePopupMenu();
    HWND hwnd;
    MSG msg;

    swallow_mode = argc > 1 && !strcmp( argv[1], "swallow" );
    t0 = GetTickCount();
    say( "mode: %s", swallow_mode ? "swallow (Live-like)" : "pass (DefWindowProc sees everything)" );

    RegisterClassA( &wc );
    AppendMenuA( file, MF_STRING, 100, "&Open" );
    AppendMenuA( edit, MF_STRING, 101, "&Copy" );
    AppendMenuA( bar, MF_POPUP, (UINT_PTR)file, "&File" );
    AppendMenuA( bar, MF_POPUP, (UINT_PTR)edit, "&Edit" );

    hwnd = CreateWindowA( "altnum_test", "altnum", WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                          100, 100, 400, 300, 0, bar, 0, 0 );
    SetForegroundWindow( hwnd );
    CreateThread( NULL, 0, inject, hwnd, 0, NULL );

    while (GetMessageA( &msg, 0, 0, 0 ))
    {
        TranslateMessage( &msg );
        DispatchMessageA( &msg );
    }
    say( "exit" );
    return 0;
}
