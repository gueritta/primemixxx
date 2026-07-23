#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <sys/time.h>
#include <poll.h>

// Skip udev hidraw scans (kernel bug: NLMSG_DONE never sent for hidraw)
// Cap infinite poll() timeouts to prevent permanent blocking

#define MAX_ENUM 32
static void *enum_ptrs[MAX_ENUM] = {0};
static char enum_subsys[MAX_ENUM][64] = {{0}};
static int enum_count = 0;

static int enum_index(void *e) {
    for (int i = 0; i < enum_count; i++)
        if (enum_ptrs[i] == e) return i;
    if (enum_count < MAX_ENUM) {
        enum_ptrs[enum_count] = e;
        return enum_count++;
    }
    return -1;
}

static void __attribute__((constructor)) init(void) {
    fprintf(stderr, "no_hid_poll: skip hidraw udev scan, cap infinite polls\n");
}

// --- udev: skip hidraw scans ---
void *udev_new(void) {
    static void *(*real)(void) = NULL;
    if (!real) real = dlsym(RTLD_NEXT, "udev_new");
    return real();
}
void udev_unref(void *u) {
    static void (*real)(void *) = NULL;
    if (!real) real = dlsym(RTLD_NEXT, "udev_unref");
    real(u);
}
void *udev_enumerate_new(void *udev) {
    static void *(*real)(void *) = NULL;
    if (!real) real = dlsym(RTLD_NEXT, "udev_enumerate_new");
    void *e = real(udev);
    enum_index(e);
    return e;
}
int udev_enumerate_add_match_subsystem(void *e, const char *s) {
    static int (*real)(void *, const char *) = NULL;
    if (!real) real = dlsym(RTLD_NEXT, "udev_enumerate_add_match_subsystem");
    int idx = enum_index(e);
    if (idx >= 0 && s) { strncpy(enum_subsys[idx], s, 63); }
    return real(e, s);
}
int udev_enumerate_scan_devices(void *e) {
    static int (*real)(void *) = NULL;
    if (!real) real = dlsym(RTLD_NEXT, "udev_enumerate_scan_devices");
    int idx = enum_index(e);
    if (idx >= 0 && !strcmp(enum_subsys[idx], "hidraw")) {
        return 0; // skip: kernel never sends NLMSG_DONE for hidraw
    }
    return real(e);
}
int udev_enumerate_scan_subsystems(void *e) {
    static int (*real)(void *) = NULL;
    if (!real) real = dlsym(RTLD_NEXT, "udev_enumerate_scan_subsystems");
    int idx = enum_index(e);
    if (idx >= 0 && !strcmp(enum_subsys[idx], "hidraw")) {
        return 0;
    }
    return real(e);
}
void *udev_enumerate_get_list_entry(void *e) {
    static void *(*real)(void *) = NULL;
    if (!real) real = dlsym(RTLD_NEXT, "udev_enumerate_get_list_entry");
    return real(e);
}
void udev_enumerate_unref(void *e) {
    static void (*real)(void *) = NULL;
    if (!real) real = dlsym(RTLD_NEXT, "udev_enumerate_unref");
    for (int i = 0; i < enum_count; i++)
        if (enum_ptrs[i] == e) enum_ptrs[i] = NULL;
    real(e);
}

// --- libusb: return error from init to short-circuit hidapi-libusb ---
// hidapi is statically linked, so we intercept libusb_init instead.
// When libusb_init fails, hidapi's libusb backend returns empty device list.
int libusb_init(void **ctx) {
    (void)ctx;
    return -1; // LIBUSB_ERROR_OTHER — makes hid_enumerate fail fast
}
void libusb_exit(void *ctx) { (void)ctx; }
// Also stub out libusb open/close functions that hidapi might call
int libusb_open(void *dev, void **handle) { (void)dev; (void)handle; return -1; }
void libusb_close(void *handle) { (void)handle; }
int libusb_get_device_list(void *ctx, void ***list) { (void)ctx; *list = NULL; return 0; }
void libusb_free_device_list(void **list, int unref) { (void)list; (void)unref; }
int libusb_get_device_descriptor(void *dev, void *desc) { (void)dev; (void)desc; return -1; }

// --- poll: cap infinite timeouts to prevent permanent blocking ---
int poll(struct pollfd *fds, nfds_t nfds, int timeout) {
    static int (*real)(struct pollfd *, nfds_t, int) = NULL;
    if (!real) real = dlsym(RTLD_NEXT, "poll");
    if (timeout < 0) {
        return real(fds, nfds, 10); // cap to 10ms instead of infinite
    }
    return real(fds, nfds, timeout);
}
