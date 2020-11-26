//
//  memory_scanner.h
//  MacSplit.Celeste
//
//  Created by Pierce Corcoran on 11/3/20.
//  Copyright © 2020 Pierce Corcoran. All rights reserved.
//

#ifndef memory_scanner_h
#define memory_scanner_h

#include <stdbool.h>
#include <stdio.h>
#include <mach/mach.h>

typedef struct memscan_target_t {
    pid_t pid;
    mach_port_name_t task;
} memscan_target;

// === Signatures ===
typedef struct memscan_signature_t {
    /**
     The length of the signature
     */
    size_t length;
    /**
     The signature
     */
    unsigned char *signature;
    /**
     A mask defining which bytes are meaningful. Any false values will be ignored.
     */
    bool *mask;
} memscan_signature;

/// Parse the passed signature as a hex string, with `??` in place of bytes that should be ignored
memscan_signature memscan_signature_parse(const char *signature_string);

/// Create a signature by copying the passed buffers
memscan_signature memscan_signature_create(const unsigned char *signature, const bool *mask, size_t length);

/// Create a signature by copying the passed signature
memscan_signature memscan_signature_copy(const memscan_signature *other);

/// Free the passed signature
void memscan_signature_free(memscan_signature signature);

// === Scanner ===
/**
 An opaque struct storing the current state of a memory scan
 */
struct memscan_scanner_t;
/**
 An opaque struct storing the current state of a memory scan
 */
typedef struct memscan_scanner_t memscan_scanner;

/**
 Options to filter the regions that will be scanned
 */
typedef struct memscan_filter_t {
    vm_address_t start_address;
    vm_address_t end_address;
} memscan_filter;

/**
 Create a new memory scanner for the given target using the given signature. This can be freed using `memscan_scanner_free`
 */
memscan_scanner *memscan_scanner_create(memscan_target target, const memscan_signature *signature, memscan_filter filter);

/**
 Free a memory scanner
 */
void memscan_scanner_free(memscan_scanner *scanner);

typedef struct memscan_match_t {
    // region info?
    /**
     The address of the match. This points to the start of the signature.
     */
    vm_address_t address;
} memscan_match;

/**
 An error that occurred during scanning, or MEMSCAN_SUCCESS if no error occurred.
 Anything in the MEMSCAN_ERROR_KERN_MASK is the value of a kern_return_t return code
 Anything in the MEMSCAN_ERROR_SCAN_MASK is a MEMSCAN_ERROR_* error
 */
typedef int memscan_error_t;

/**
 The scan completed successfully, even if nothing was found.
 */
#define MEMSCAN_SUCCESS 0

#define MEMSCAN_ERROR_KERN_MASK 0xff
#define MEMSCAN_ERROR_SCAN_MASK (~0xff)

/**
 An error occurred getting the page size
 */
#define MEMSCAN_ERROR_PAGE_SIZE_FAILED (1 << 8)
/**
 An error occurred getting the region info
 */
#define MEMSCAN_ERROR_VM_REGION_INFO_FAILED (2 << 8)
/**
 An error occurred reading memory
 */
#define MEMSCAN_ERROR_VM_READ_MEMORY_FAILED (3 << 8)
/**
 An error occurred writing memory
 */
#define MEMSCAN_ERROR_VM_WRITE_MEMORY_FAILED (4 << 8)

/**
 Scan until the next match. If a match was found, it is placed `match` and this function returns true, otherwise this function returns false. If the passed error pointer is non-null, any errors will be put there.
 */
bool memscan_scanner_next(memscan_scanner *scanner, memscan_match *match, memscan_error_t *error);

void *memscan_read(memscan_target target, vm_address_t start, vm_offset_t length, memscan_error_t *error);

#endif /* memory_scanner_h */
