// Cuts the network of one app on the simulator, which shares the Mac's: every way out is refused and written down.
// Inserted with DYLD_INSERT_LIBRARIES by OortTrialTests, never shipped. A probe from CFNetwork shows the cut holds.
#import <Foundation/Foundation.h>
#import <Network/Network.h>
#include <arpa/inet.h>
#include <errno.h>
#include <netdb.h>
#include <netinet/in.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>

static void say(NSString *line) {
    const char *path = getenv("OORT_NET_LOG");
    FILE *file = path ? fopen(path, "a") : NULL;
    if (file) { fprintf(file, "%s\n", line.UTF8String); fclose(file); }
}

// This Mac and local sockets stay: the test runner talks over them.
static int local(const struct sockaddr *address) {
    if (!address) return 1;
    if (address->sa_family == AF_INET) return (ntohl(((const struct sockaddr_in *)address)->sin_addr.s_addr) >> 24) == 127;
    if (address->sa_family == AF_INET6) return IN6_IS_ADDR_LOOPBACK(&((const struct sockaddr_in6 *)address)->sin6_addr);
    return 1;
}

static NSString *words(const struct sockaddr *address) {
    char text[INET6_ADDRSTRLEN] = "?";
    if (address->sa_family == AF_INET) inet_ntop(AF_INET, &((const struct sockaddr_in *)address)->sin_addr, text, sizeof text);
    else inet_ntop(AF_INET6, &((const struct sockaddr_in6 *)address)->sin6_addr, text, sizeof text);
    return @(text);
}

static int cut_connect(int s, const struct sockaddr *address, socklen_t length) {
    if (local(address)) return connect(s, address, length);
    say([@"blocked connect " stringByAppendingString:words(address)]);
    errno = ENETUNREACH;
    return -1;
}

static int cut_connectx(int s, const sa_endpoints_t *ends, sae_associd_t id, unsigned int flags, const struct iovec *iov, unsigned int count, size_t *sent, sae_connid_t *conn) {
    if (!ends || local(ends->sae_dstaddr)) return connectx(s, ends, id, flags, iov, count, sent, conn);
    say([@"blocked connectx " stringByAppendingString:words(ends->sae_dstaddr)]);
    errno = ENETUNREACH;
    return -1;
}

static ssize_t cut_sendto(int s, const void *data, size_t size, int flags, const struct sockaddr *address, socklen_t length) {
    if (local(address)) return sendto(s, data, size, flags, address, length);
    say([@"blocked sendto " stringByAppendingString:words(address)]);
    errno = ENETUNREACH;
    return -1;
}

static int cut_getaddrinfo(const char *host, const char *port, const struct addrinfo *hints, struct addrinfo **result) {
    if (!host || !strcmp(host, "localhost") || !strcmp(host, "127.0.0.1") || !strcmp(host, "::1")) return getaddrinfo(host, port, hints, result);
    say([NSString stringWithFormat:@"blocked getaddrinfo %s", host]);
    return EAI_NONAME;
}

// Network.framework's connections are written down, then left to the refusals above: ending one here would break CFNetwork.
static void seen_nw_connection_start(nw_connection_t connection) {
    nw_endpoint_t end = nw_connection_copy_endpoint(connection);
    const char *host = end ? nw_endpoint_get_hostname(end) : NULL;
    if (!host || (strcmp(host, "localhost") && strcmp(host, "127.0.0.1") && strcmp(host, "::1")))
        say([NSString stringWithFormat:@"blocked? nw_connection %s", host ?: "?"]);
    nw_connection_start(connection);
}

#define CUT(ours, theirs) \
    __attribute__((used)) static const struct { const void *a, *b; } interpose_##theirs __attribute__((section("__DATA,__interpose"))) = { (const void *)&ours, (const void *)&theirs };
CUT(cut_connect, connect)
CUT(cut_connectx, connectx)
CUT(cut_sendto, sendto)
CUT(cut_getaddrinfo, getaddrinfo)
CUT(seen_nw_connection_start, nw_connection_start)

__attribute__((constructor)) static void probe(void) {
    say(@"cut loaded");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        configuration.timeoutIntervalForRequest = 8;
        say(@"PROBE start https://example.com");
        [[[NSURLSession sessionWithConfiguration:configuration] dataTaskWithURL:[NSURL URLWithString:@"https://example.com/"]
                                                              completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            say(error ? [NSString stringWithFormat:@"PROBE failed %ld", (long)error.code] : @"PROBE got an answer: the cut does not hold");
            // What the probe itself caused may still be written for a moment.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ say(@"PROBE end"); });
        }] resume];
    });
}
