//
//  memory_scanner.c
//  SwiftSplit.Celeste
//
//  Created by Pierce Corcoran on 11/3/20.
//  Copyright © 2020 Pierce Corcoran. All rights reserved.
//

#include "memory_scanner.h"

#include <stdlib.h>
#include <libproc.h>
#include <sys/errno.h>

// === Signatures ===

memscan_signature memscan_signature_parse(const char *signature_string) {
    char parse_string[3] = {0,0,0};
    size_t length = strlen(signature_string) / 2;
    
    memscan_signature signature = {
        .length = length,
        .signature = malloc(sizeof(unsigned char) * length),
        .mask = malloc(sizeof(bool) * length)
    };
    
    for(size_t i = 0; i < length; i++) {
        parse_string[0] = signature_string[i * 2];
        parse_string[1] = signature_string[i * 2 + 1];
        if(parse_string[0] == '?' || parse_string[1] == '?') {
            signature.signature[i] = 0;
            signature.mask[i] = false;
        } else {
            signature.signature[i] = (char)strtol(parse_string, NULL, 16);
            signature.mask[i] = true;
        }
    }
    
    return signature;
}

memscan_signature memscan_signature_create(const unsigned char *signature, const bool *mask, size_t length) {
    memscan_signature mem_signature = {
        .length = length,
        .signature = malloc(sizeof(unsigned char) * length),
        .mask = malloc(sizeof(bool) * length)
    };
    
    memcpy(mem_signature.signature, signature, length * sizeof(unsigned char));
    memcpy(mem_signature.mask, mask, length * sizeof(bool));
    
    return mem_signature;
}

memscan_signature memscan_signature_copy(const memscan_signature *other) {
    memscan_signature mem_signature = {
        .length = other->length,
        .signature = malloc(sizeof(unsigned char) * other->length),
        .mask = malloc(sizeof(bool) * other->length)
    };
    
    memcpy(mem_signature.signature, other->signature, other->length * sizeof(unsigned char));
    memcpy(mem_signature.mask, other->mask, other->length * sizeof(bool));
    
    return mem_signature;
}

void memscan_signature_free(memscan_signature signature) {
    free(signature.mask);
    free(signature.signature);
}

// === Scanners ===

struct memscan_scanner_t {
    // --- configuration ---
    /**
     The target process to scan
     */
    memscan_target target;
    /**
     The signature to scan for
     */
    const memscan_signature *signature;
    /**
     The filter for regions to scan
     */
    memscan_filter filter;
    
    // --- virtual memory iteration ---
    /**
     The current region's address
     */
    vm_address_t region_address;
    /**
     The current region's size
     */
    vm_size_t region_size;
    /**
     The current region's vm_region_recurse_64 submap depth.
     */
    uint32_t region_depth;
    
    // --- region scanning ---
    /**
     The page size. A zero value is also used to detect the first call to memscan_scanner_next
     */
    vm_size_t page_size;
    /**
     The address of the currently loaded page
     */
    vm_address_t page_address;
    
    /**
     The contents of the currently loaded page
     */
    unsigned char *page_buffer;
    
    /**
     The contents of the previous loaded page. This is present to allow rolling back when a match across a boundary fails. If we don't roll back, then we won't find matches that overlap a failed match.
     */
    unsigned char *previous_page_buffer;
    
    /**
     The address of the current search. If this is negative, it's addressing into the previous_page_buffer (-1 is the last, -2 the one before that, etc.)
     */
    int scan_index;
};

void memscan_scanner_free(memscan_scanner *scanner) {
    if(scanner->page_size != 0) {
        free(scanner->page_buffer);
        free(scanner->previous_page_buffer);
    }
}

memscan_scanner *memscan_scanner_create(memscan_target target, const memscan_signature *signature, memscan_filter filter) {
    memscan_scanner *scanner = (memscan_scanner *)malloc(sizeof(memscan_scanner));
    *scanner = (memscan_scanner) {
        .target = target,
        .signature = signature,
        .filter = filter,
        .region_address = 0,
        .region_depth = 0,
        .page_size = 0,
    };
    return scanner;
}

/**
 Find the next (filtered) region. Returns true if a region was found, false otherwise.
 */
bool memscan_scanner_next_region(memscan_scanner *scanner, memscan_error *error) {
    if(scanner->region_address == 0) {
        scanner->region_address = scanner->filter.start_address;
    }
    
    char buf[PATH_MAX];
    
    while(true) {
        // advance to the end of the current region and start searching from there
        scanner->region_address += scanner->region_size;
        
        mach_msg_type_number_t count = VM_REGION_SUBMAP_INFO_COUNT_64;
        struct vm_region_submap_info_64 info;
        
        // finds the next memory region with an address >= target_address
        // puts that region's starting address and size in the passed pointers
        // region_depth is the submap depth, but at the end of a submap vm_region_recurse_64 will decrement it as needed
        // additional information is put into &info
        // still have no idea what count is for
        kern_return_t kr = vm_region_recurse_64(scanner->target.task,
                                                &scanner->region_address, &scanner->region_size, &scanner->region_depth,
                                                (vm_region_recurse_info_t)&info, &count);
        
        if(kr == KERN_INVALID_ADDRESS ) {
            // we've reached the end of the line
            return false;
        }
        
        if(kr) {
            // we've encountered an actual error
            if(error) *error = (memscan_error) {
                .memscan = MEMSCAN_ERROR_VM_REGION_INFO_FAILED,
                .mach = kr
            };
            return false;
        }

        if (info.is_submap) {
            scanner->region_depth++;
            continue; // we must go deeper!
        }
        
        bool valid = true;
        // apply filters
        valid = valid && (info.protection & VM_PROT_DEFAULT) == VM_PROT_DEFAULT;
        
//        int ret = proc_regionfilename(scanner->target.pid, scanner->region_address, buf, sizeof(buf));
        if(valid) {
            return true;
        }
    }
    
}

bool memscan_scanner_next(memscan_scanner *scanner, memscan_match *match, memscan_error *error) {
    bool is_first = false;
    if(scanner->page_size == 0) {
        // this is the first call. Get everything set up.
        vm_size_t page_size;
        kern_return_t kr = host_page_size(mach_host_self(), &page_size);
        if(kr) {
            printf("Failed to get page size: host_page_size returned %d", kr);
            if(error) *error = (memscan_error) { .memscan = MEMSCAN_ERROR_PAGE_SIZE_FAILED, .mach = kr };
            return false;
        }
        scanner->page_size = page_size;
        scanner->page_buffer = (unsigned char*)malloc(page_size);
        scanner->previous_page_buffer = (unsigned char*)malloc(page_size);
        is_first = true;
    }
    
    size_t match_progress = 0;
    
    while(true) {
        bool load_page = false; // whether we should load the data at page_address into page_buffer
        
        // if we're at the end of a page, step forward to the start of the next one
        if(scanner->scan_index == scanner->page_size) {
            scanner->page_address += scanner->page_size;
            scanner->scan_index = 0;
            load_page = true;
        }
        
        // if we're past the end of the current region (or if the region is uninitialized, `0 >= 0 + 0`), find the next one
        // don't do anything if we've rolled back into the previous page
        if(scanner->scan_index >= 0 && scanner->page_address + scanner->scan_index >= scanner->region_address + scanner->region_size) {
            if(!memscan_scanner_next_region(scanner, error)) {
                // we couldn't find another region. either we just ran out or we
                // ran into an error. The result will have been put into `error`
                return false;
            }

            // if this new region isn't contiguous, reset the match progress
            if(scanner->page_address + scanner->scan_index != scanner->region_address) {
                match_progress = 0;
            }
            
            // jump to this new page
            scanner->page_address = scanner->region_address;
            scanner->scan_index = 0;
            
            // we need to load this new page
            load_page = true;
        }

        // load the page at page_address into page_buffer
        if(load_page) {
            if(scanner->filter.end_address != 0 && scanner->page_address > scanner->filter.end_address) {
                return false;
            }
            
            vm_size_t data_cnt;
            
            unsigned char* _last = scanner->previous_page_buffer;
            scanner->previous_page_buffer = scanner->page_buffer;
            scanner->page_buffer = _last;

            kern_return_t kr = vm_read_overwrite(scanner->target.task, scanner->page_address, scanner->page_size,
                                                 (vm_address_t)scanner->page_buffer, &data_cnt);
            
            if(kr) {
                if(error) *error = (memscan_error) { .memscan = MEMSCAN_ERROR_VM_READ_MEMORY_FAILED, .mach = kr };
                return false;
            }
        }
        
        // find the value at the scan index. If the index is negative (like it can be when rolling back), index into the end of the previous page.
        unsigned char page_value;
        if(scanner->scan_index < 0) {
            page_value = scanner->previous_page_buffer[scanner->page_size + scanner->scan_index];
        } else {
            page_value = scanner->page_buffer[scanner->scan_index];
        }
        
        if(scanner->signature->mask[match_progress] && page_value != scanner->signature->signature[match_progress]) {
            // the match failed. Roll back to right after this match attempt started.
            // If this match failed on the first character has the effect of incrementing
            if(match_progress > 0) {
                scanner->scan_index -= match_progress; // first roll back to exactly where it started
            }
            scanner->scan_index++; // then step forward by one
            match_progress = 0;
        } else {
            // the match is progressing
            match_progress++;
            scanner->scan_index++;
            
            if(match_progress == scanner->signature->length) {
                *match = (memscan_match){
                    .address = scanner->page_address + scanner->scan_index - match_progress
                };
                return true;
            }
        }
    }

    return false;
}

void *memscan_read(memscan_target target, vm_address_t start, vm_offset_t length, memscan_error *error) {
    vm_size_t data_cnt;
    
    void* data = (void*)malloc(length);
    
    kern_return_t kr = vm_read_overwrite(target.task, start, length, (vm_address_t)data, &data_cnt);
    
    if(kr) {
        *error = (memscan_error) { .memscan = MEMSCAN_ERROR_VM_READ_MEMORY_FAILED, .mach = kr };
        free(data);
        return 0;
    }
    
    return data;
}
