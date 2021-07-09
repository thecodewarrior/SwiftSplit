//
//  MonoProcess.swift
//  SwiftSplit
//
//  Created by Pierce Corcoran on 7/8/21.
//  Copyright © 2021 Pierce Corcoran. All rights reserved.
//

import Foundation

class RmaProcess {
    let target: MemscanTarget
    let filter: MemscanFilter
    
    init(target: MemscanTarget, filter: MemscanFilter) {
        self.target = target
        self.filter = filter
    }
    
    func findPointer(by signature: MemscanSignature) throws -> RmaPointer? {
        let pointers = try findPointers(by: signature, max: 1)
        if pointers.count == 0 {
            return nil
        }
        return pointers[0]
    }
    
    func findPointers(by signature: MemscanSignature, max: Int = Int.max) throws -> [RmaPointer] {
        var pointers: [RmaPointer] = []
        let scanner = MemscanScanner(target: target, signature: signature, filter: filter)
        while let match = try scanner.next() {
            pointers.append(pointer(at: match.address))
            if pointers.count >= max {
                break
            }
        }
        return pointers
    }
    
    func pointer(at address: vm_address_t) -> RmaPointer {
        return RmaPointer(target, at: address)
    }
}

struct RmaPointer {
    private let target: MemscanTarget
    let address: vm_address_t
    
    init(_ target: MemscanTarget, at address: vm_address_t) {
        self.target = target
        self.address = address
    }
    
    func offset(by offset: Int) -> RmaPointer {
        return RmaPointer(target, at: address.advanced(by: offset))
    }

    func value<T>(at offset: Int = 0, as type: T.Type = T.self) throws -> T {
        let result = try target.read(at: address.advanced(by: offset), count: UInt(MemoryLayout<T>.size))
        return result.buffer.load(as: type)
    }

    func value(at offset: Int = 0) throws -> RmaPointer {
        return RmaPointer(target, at: try self.value(at: offset))
    }
    
    func read(bytes: vm_offset_t) throws -> [UInt8] {
        let result = try target.read(at: address, count: bytes)
        return Array(result.buffer.bindMemory(to: UInt8.self))
    }
    
    func preload(size: vm_offset_t) throws -> RmaValue {
        return RmaValue(target, result: try target.read(at: address, count: size))
    }
    
    func raw(at offset: Int, count: vm_offset_t) throws -> MemscanReadResult {
        return try target.read(at: address.advanced(by: offset), count: count)
    }
}

struct RmaValue {
    private let target: MemscanTarget
    private let result: MemscanReadResult
    
    init(_ target: MemscanTarget, result: MemscanReadResult) {
        self.target = target
        self.result = result
    }
    
    func value<T>(at offset: Int = 0, as type: T.Type = T.self) -> T {
        return result.buffer.load(fromByteOffset: offset, as: type)
    }

    func value(at offset: Int = 0) -> RmaPointer {
        return RmaPointer(target, at: self.value(at: offset))
    }
}

extension MemscanSignature : ExpressibleByStringLiteral {
    typealias StringLiteralType = String
    
    convenience init(stringLiteral value: String) {
        self.init(parsing: value)
    }
}

extension MemscanSignature {
    convenience init(address: vm_address_t) {
        self.init(from: withUnsafeBytes(of: address.littleEndian, Array.init))
    }
}

