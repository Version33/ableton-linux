#define _GNU_SOURCE

/*
 * pipewire-version-probe: report the loaded client library and connected
 * daemon versions without depending on PipeWire command-line utilities.
 */
#include <errno.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <pipewire/pipewire.h>

struct probe {
    struct pw_main_loop *main_loop;
    int                  sync_seq;
    int                  result;
    char                 daemon_version[128];
};

static void core_info(void *userdata, const struct pw_core_info *info)
{
    struct probe *probe = userdata;

    if (info != NULL && info->version != NULL)
        snprintf(probe->daemon_version, sizeof(probe->daemon_version), "%s", info->version);
}

static void core_done(void *userdata, uint32_t id, int seq)
{
    struct probe *probe = userdata;

    if (id == PW_ID_CORE && seq == probe->sync_seq)
        pw_main_loop_quit(probe->main_loop);
}

static void core_error(void *userdata, uint32_t id, int seq, int result, const char *message)
{
    struct probe *probe = userdata;

    (void)id;
    (void)seq;
    fprintf(stderr, "pipewire-version-probe: core error %d: %s\n", result,
            message != NULL ? message : "unknown error");
    probe->result = result < 0 ? result : -EIO;
    pw_main_loop_quit(probe->main_loop);
}

static void probe_timeout(void *userdata, uint64_t expirations)
{
    struct probe *probe = userdata;

    (void)expirations;
    probe->result = -ETIMEDOUT;
    pw_main_loop_quit(probe->main_loop);
}

static const struct pw_core_events core_events = {
    .version = PW_VERSION_CORE_EVENTS,
    .info  = core_info,
    .done  = core_done,
    .error = core_error,
};

int main(int argc, char **argv)
{
    struct probe        probe = { 0 };
    struct pw_context  *context = NULL;
    struct pw_core     *core = NULL;
    struct pw_loop     *loop;
    struct spa_hook     core_listener = { 0 };
    struct spa_source  *timer = NULL;
    struct timespec     timeout = { .tv_sec = 5, .tv_nsec = 0 };
    const char         *client_version;
    bool                client_only = false;
    int                 status = EXIT_FAILURE;

    if (argc == 2 && strcmp(argv[1], "--client") == 0)
        client_only = true;
    else if (argc != 1) {
        fprintf(stderr, "usage: %s [--client]\n", argv[0]);
        return 2;
    }

    pw_init(&argc, &argv);
    client_version = pw_get_library_version();
    if (client_version == NULL || client_version[0] == '\0') {
        fprintf(stderr, "pipewire-version-probe: loaded client version unavailable\n");
        goto out;
    }
    if (client_only) {
        printf("client=%s\n", client_version);
        status = EXIT_SUCCESS;
        goto out;
    }

    probe.main_loop = pw_main_loop_new(NULL);
    if (probe.main_loop == NULL) {
        fprintf(stderr, "pipewire-version-probe: cannot create main loop: %s\n", strerror(errno));
        goto out;
    }
    loop = pw_main_loop_get_loop(probe.main_loop);
    context = pw_context_new(loop, NULL, 0);
    if (context == NULL) {
        fprintf(stderr, "pipewire-version-probe: cannot create context: %s\n", strerror(errno));
        goto out;
    }
    core = pw_context_connect(context, NULL, 0);
    if (core == NULL) {
        fprintf(stderr, "pipewire-version-probe: cannot connect to daemon: %s\n", strerror(errno));
        goto out;
    }
    pw_core_add_listener(core, &core_listener, &core_events, &probe);

    timer = pw_loop_add_timer(loop, probe_timeout, &probe);
    if (timer == NULL || pw_loop_update_timer(loop, timer, &timeout, NULL, false) < 0) {
        fprintf(stderr, "pipewire-version-probe: cannot arm timeout\n");
        goto out;
    }
    probe.sync_seq = pw_core_sync(core, PW_ID_CORE, 0);
    if (probe.sync_seq < 0) {
        fprintf(stderr, "pipewire-version-probe: cannot synchronize with daemon\n");
        goto out;
    }
    probe.result = 0;
    if (pw_main_loop_run(probe.main_loop) < 0 || probe.result < 0)
        goto out;
    if (probe.daemon_version[0] == '\0') {
        fprintf(stderr, "pipewire-version-probe: daemon version unavailable\n");
        goto out;
    }

    printf("client=%s\ndaemon=%s\n", client_version, probe.daemon_version);
    status = EXIT_SUCCESS;

out:
    if (timer != NULL)
        pw_loop_destroy_source(pw_main_loop_get_loop(probe.main_loop), timer);
    if (core != NULL) {
        spa_hook_remove(&core_listener);
        pw_core_disconnect(core);
    }
    if (context != NULL)
        pw_context_destroy(context);
    if (probe.main_loop != NULL)
        pw_main_loop_destroy(probe.main_loop);
    pw_deinit();
    return status;
}
