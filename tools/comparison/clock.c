// Test-process clock only. Monotonic clocks remain real so worker deadlines work.
// No part of this library is linked into the app or the reference implementation.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <sys/time.h>

static long long fixture_millis(void) {
    const char *path = getenv("ANKI_COMPARISON_CLOCK_FILE");
    if (!path) return -1;
    FILE *file = fopen(path, "r");
    if (!file) return -1;
    long long value = -1;
    if (fscanf(file, "%lld", &value) != 1) value = -1;
    fclose(file);
    return value;
}

int clock_gettime(clockid_t id, struct timespec *value) {
    long long millis = (id == CLOCK_REALTIME || id == CLOCK_REALTIME_COARSE) ? fixture_millis() : -1;
    if (millis >= 0) {
        value->tv_sec = millis / 1000;
        value->tv_nsec = (millis % 1000) * 1000000;
        return 0;
    }
    int (*original)(clockid_t, struct timespec *) = dlsym(RTLD_NEXT, "clock_gettime");
    return original(id, value);
}

int gettimeofday(struct timeval *value, void *zone) {
    long long millis = fixture_millis();
    if (millis >= 0) {
        value->tv_sec = millis / 1000;
        value->tv_usec = (millis % 1000) * 1000;
        return 0;
    }
    int (*original)(struct timeval *, void *) = dlsym(RTLD_NEXT, "gettimeofday");
    return original(value, zone);
}

time_t time(time_t *value) {
    long long millis = fixture_millis();
    time_t result;
    if (millis >= 0) result = millis / 1000;
    else {
        time_t (*original)(time_t *) = dlsym(RTLD_NEXT, "time");
        result = original(NULL);
    }
    if (value) *value = result;
    return result;
}
