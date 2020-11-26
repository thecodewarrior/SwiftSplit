//
//  MemoryScanner.swift
//  MacSplit
//
//  Created by Pierce Corcoran on 11/4/20.
//  Copyright © 2020 Pierce Corcoran. All rights reserved.
//

import Foundation

enum MemscanError : Error {
    case errorGettingTask(result: kern_return_t)
    case scanError(result: memscan_error_t)
    case readError(result: memscan_error_t)
    case readNullPointer
}

class MemscanSignature {
    var native: memscan_signature

    /**
     Create a signature with a mask. If the mask size differs from the signature size, it will be trimmed or extended with `true` values
     */
    init(from signature: [UInt8], mask: [Bool]) {
        let length = signature.count
        var resizedMask = [Bool](repeating: true, count: length)
        resizedMask.replaceSubrange(0..<min(mask.count, length), with: mask)

        self.native = memscan_signature_create(signature, resizedMask, length)
    }
    
    convenience init(from signature: [UInt8]) {
        self.init(from: signature, mask: [])
    }
    
    /**
     Create a signature with a mask. If the mask size differs from the signature size, it will be trimmed or extended with `true` values
     */
    init(from signature: UnsafeRawBufferPointer, mask: UnsafeBufferPointer<Bool>) {
        let length = signature.count
        var resizedMask = [Bool](repeating: true, count: length)
        resizedMask.replaceSubrange(0..<min(mask.count, length), with: mask)
        
        self.native = memscan_signature_create(signature.bindMemory(to: UInt8.self).baseAddress, resizedMask, length)
    }
    
    convenience init(from signature: UnsafeRawBufferPointer) {
        let maskBuf = UnsafeMutablePointer<Bool>.allocate(capacity: signature.count)
        maskBuf.initialize(repeating: true, count: signature.count)
        self.init(from: signature, mask: UnsafeBufferPointer<Bool>(start: maskBuf, count: signature.count))
        maskBuf.deallocate()
    }
    
    /**
     Create a signature from a hex string with `??` in place of any bytes that should be ignored.
     */
    init(parsing signatureString: String) {
        self.native = memscan_signature_parse(signatureString)
    }
    
    deinit {
        memscan_signature_free(native)
    }
    
    func debugString() -> String {
        var str = ""
        for (index, byte) in UnsafeBufferPointer<UInt8>(start: native.signature, count: native.length).enumerated() {
            if(native.mask[index]) {
                str += String(format:"%02x", byte)
            } else {
                str += "??"
            }
        }
        return str
    }
}

class MemscanTarget {
    let native: memscan_target
    
    init(pid: pid_t) throws {
        var task: mach_port_name_t = 0
        let kernResult = task_for_pid(mach_task_self_, pid, &task)
        if(kernResult != KERN_SUCCESS) {
            throw MemscanError.errorGettingTask(result: kernResult)
        }
        self.native = memscan_target(pid: pid, task: task)
    }
    
    func read(at pointer: vm_address_t, count: vm_offset_t) throws -> MemscanReadResult {
        var error: memscan_error_t = 0
        let data = memscan_read(native, pointer, count, &error)
        if(error != MEMSCAN_SUCCESS) {
            throw MemscanError.readError(result: error)
        }
        guard data != nil else {
            throw MemscanError.readNullPointer
        }
        return MemscanReadResult(with: UnsafeRawBufferPointer(start: data, count: Int(count)))
    }
}

class MemscanReadResult {
    let buffer: UnsafeRawBufferPointer
    
    init(with buffer: UnsafeRawBufferPointer) {
        self.buffer = buffer
    }

    deinit {
        buffer.deallocate()
    }
    
    func debugString() -> String {
        return debugString(withCursor: -1)
    }
    
    func debugString(withCursor cursor: Int) -> String {
        var str = ""
        for (index, byte) in buffer.enumerated() {
            if(index == cursor) {
                str += "|"
            }
            str += String(format:"%02x", byte)
        }
        return str
    }
    
    func debugStringReversed(withCursor cursor: Int) -> String {
        var str = ""
        for (index, byte) in buffer.enumerated().reversed() {
            str += String(format:"%02x", byte)
            if(index == cursor) {
                str += "|"
            }
        }
        return str
    }

}

class MemscanFilter {
    let native: memscan_filter
    
    init(startAddress: vm_address_t, endAddress: vm_address_t) {
        native = memscan_filter(start_address: startAddress, end_address: endAddress)
    }
    init() {
        native = memscan_filter()
    }
}

class MemscanScanner {
    let native: OpaquePointer
    private var nativeSignature: UnsafePointer<memscan_signature>
    
    init(target: MemscanTarget, signature: MemscanSignature, filter: MemscanFilter) {
        let nativeSignature = UnsafeMutablePointer<memscan_signature>.allocate(capacity: 1)
        nativeSignature.initialize(to: memscan_signature_copy(&signature.native))
        self.nativeSignature = UnsafePointer(nativeSignature)
        self.native = memscan_scanner_create(target.native, self.nativeSignature, filter.native)
    }
    
    func next() throws -> MemscanMatch? {
        var match = memscan_match()
        var error: memscan_error_t = 0
        if(memscan_scanner_next(native, &match, &error)) {
            return MemscanMatch(native: match)
        }
        if(error != MEMSCAN_SUCCESS) {
            throw MemscanError.scanError(result: error)
        }
        return nil
    }

    deinit {
        memscan_scanner_free(native)
        memscan_signature_free(nativeSignature.pointee)
        nativeSignature.deallocate()
    }
}

class MemscanMatch {
    let native: memscan_match
    
    var address: vm_address_t {
        get {
            return native.address
        }
    }

    init(native: memscan_match) {
        self.native = native
    }
}
