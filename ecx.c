/*
 * ecx.c - EC direct access for SCHENKER KEY 17 Pro M24 (Clevo/Tongfang VK35)
 *
 * Talks to the embedded controller via the ACPI EC ports (0x62 data, 0x66 cmd).
 * ioperm must cover BOTH ports (0x62/2 and 0x66/2), otherwise port 0x62 access
 * faults (general protection fault).
 *
 * Usage:
 *   ecx dump <hexstart> <hexend>   read EC RAM range [start..end] (offsets)
 *   ecx write <hexaddr> <hexval>   write one byte to EC RAM offset
 *   ecx burst 0|1                  disable/enable EC burst mode (0x83/0x82)
 *
 * ACPI EC protocol over ports:
 *   write: outb(0x81,0x66); outb(addr,0x62); outb(val,0x62)  (each gated on IBF)
 *   read : outb(0x80,0x66); outb(addr,0x62); inb(0x62)        (wait for OBF)
 * Register offsets used by fan control (RAM1 base 0xFE0B0100):
 *   0xA0 ACMD (0xB8 read/0xD8 write), 0xA1 ADAT, 0xA2 ABUF
 *
 * Build: gcc -O2 -Wall -o ecx ecx.c    (run as root, needs ioperm)
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <sys/io.h>

#define EC_DATA 0x62
#define EC_CMD  0x66

#define EC_SC_READ  0x80
#define EC_SC_WRITE 0x81
#define EC_BURST_ENABLE  0x82
#define EC_BURST_DISABLE 0x83

#define EC_IBF 0x02   /* input buffer full */
#define EC_OBF 0x01   /* output buffer full */
#define EC_SCI 0x20
#define EC_SMI 0x40

static int ec_wait_ready(void)
{
    unsigned char s;
    int i;
    for (i = 0; i < 10000; i++) {
        s = inb(EC_CMD);
        if (!(s & EC_IBF))
            return 0;
        usleep(10);
    }
    fprintf(stderr, "[ecx] timeout waiting for EC ready (status=0x%02x)\n", s);
    return -1;
}

static int ec_wait_obf(void)
{
    unsigned char s;
    int i;
    for (i = 0; i < 10000; i++) {
        s = inb(EC_CMD);
        if (s & EC_OBF)
            return 0;
        usleep(10);
    }
    fprintf(stderr, "[ecx] timeout waiting for EC OBF (status=0x%02x)\n", s);
    return -1;
}

static int ec_read_byte(unsigned int addr)
{
    if (ec_wait_ready() < 0) return -1;
    outb(EC_SC_READ, EC_CMD);
    if (ec_wait_ready() < 0) return -1;
    outb((unsigned char)addr, EC_DATA);
    if (ec_wait_obf() < 0) return -1;
    return inb(EC_DATA);
}

static int ec_write_byte(unsigned int addr, unsigned char val)
{
    if (ec_wait_ready() < 0) return -1;
    outb(EC_SC_WRITE, EC_CMD);
    if (ec_wait_ready() < 0) return -1;
    outb((unsigned char)addr, EC_DATA);
    if (ec_wait_ready() < 0) return -1;
    outb(val, EC_DATA);
    return 0;
}

static int ec_set_burst(int on)
{
    if (ec_wait_ready() < 0) return -1;
    outb(on ? EC_BURST_ENABLE : EC_BURST_DISABLE, EC_CMD);
    usleep(1000);
    return 0;
}

static unsigned int parse_hex(const char *s)
{
    return (unsigned int)strtoul(s, NULL, 16);
}

static void usage(const char *argv0)
{
    fprintf(stderr, "usage:\n"
            "  %s dump <hexstart> <hexend>   read EC RAM range [start..end]\n"
            "  %s write <hexaddr> <hexval>   write one byte to EC RAM offset\n"
            "  %s burst 0|1                  disable/enable EC burst mode\n",
            argv0, argv0, argv0);
}

int main(int argc, char **argv)
{
    if (argc < 2) {
        usage(argv[0]);
        return 1;
    }

    if (ioperm(EC_DATA, 2, 1) != 0 ||
        ioperm(EC_CMD,  2, 1) != 0) {
        fprintf(stderr, "[ecx] ioperm failed: %s\n", strerror(errno));
        return 1;
    }
    fprintf(stderr, "[ecx] ioperm rc=0 errno=%ld\n", errno);

    /* quick access self-check: expect sane status register bits */
    (void)inb(EC_CMD);
    fprintf(stderr, "[ecx] access ok\n");

    if (strcmp(argv[1], "dump") == 0 && argc == 4) {
        unsigned int s = parse_hex(argv[2]);
        unsigned int e = parse_hex(argv[3]);
        unsigned int a, count = 0;
        if (e < s) {
            fprintf(stderr, "[ecx] dump: end < start\n");
            return 1;
        }
        for (a = s; a <= e; a++) {
            int v = ec_read_byte(a);
            if (v < 0) return 1;
            printf("%02x:%02x ", a, (unsigned char)v);
            if (++count % 16 == 0) printf("\n");
        }
        if (count % 16) printf("\n");
        return 0;
    }

    if (strcmp(argv[1], "write") == 0 && argc == 4) {
        unsigned int addr = parse_hex(argv[2]);
        unsigned int val = parse_hex(argv[3]);
        if (val > 0xff) {
            fprintf(stderr, "[ecx] write: value > 0xff\n");
            return 1;
        }
        if (ec_write_byte(addr, (unsigned char)val) < 0) return 1;
        fprintf(stderr, "[ecx] write done\n");
        return 0;
    }

    if (strcmp(argv[1], "burst") == 0 && argc == 3) {
        int on = atoi(argv[2]);
        if (ec_set_burst(on) < 0) return 1;
        fprintf(stderr, "[ecx] burst %s\n", on ? "enabled" : "disabled");
        return 0;
    }

    usage(argv[0]);
    return 1;
}
