//
//  MonoMemory.swift
//  SwiftSplit
//
//  Created by Pierce Corcoran on 7/8/21.
//  Copyright © 2021 Pierce Corcoran. All rights reserved.
//

import Foundation

final class Mono {
    private init() {}
    
    static let HEADER_BYTES: Int = 16
    
    static func isNull(pointer: RmaPointer) -> Bool {
        return pointer.address == 0
    }
    
    /**
     Parse a C# string object
     
     Memory layout:
     ```
     "NUM:0"
     ```
     ```
     MonoVTable*      MonoThreadSync*    length   N    U    M    :    0
     a8cd0054c57f0000 0000000000000000   05000000 4e00 5500 4d00 3a00 3000
     0                8                  16       20
     ```
     */
    static func readString(at pointer: RmaPointer) throws -> String? {
        if isNull(pointer: pointer) { return nil }
        
        let length: Int32 = try pointer.value(at: 16)
        let stringData = try pointer.raw(at: 20, count: vm_offset_t(length) * 2)
        return String(utf16CodeUnits: stringData.buffer.bindMemory(to: unichar.self).baseAddress!, count: Int(length))
    }
    
    /**
     ```
     new int[] { 1, 2, 3, 4 }
     ```
     ```
     MonoVTable*      MonoThreadSync*  MonoArrayBounds*   length   align    1        2        3        4
     18140698947F0000 0000000000000000 0000000000000000   3F000000 00000000 01000000 02000000 03000000 04000000
     0                8                16                 24                32
     ```
     */
    static func readArray<T>(at pointer: RmaPointer, as type: T.Type = T.self) throws -> [T]? {
        if isNull(pointer: pointer) { return nil }
        let length: Int32 = try pointer.value(at: 24)
        let contents = try pointer.raw(at: 32, count: vm_offset_t(MemoryLayout<T>.size * Int(length)))

        return Array(contents.buffer.bindMemory(to: type))
    }
    
    static func readArray(at pointer: RmaPointer) throws -> [RmaPointer]? {
        if isNull(pointer: pointer) { return nil }
        let pointers: [vm_address_t]? = try readArray(at: pointer)
        return pointers?.map { RmaPointer(pointer.target, at: $0) }
    }

    static func debugMemory(around pointer: RmaPointer, before: vm_offset_t, after: vm_offset_t) throws {
        let data = try pointer.raw(at: -Int(before), count: before + after)
        print("    Forward: \(data.debugString(withCursor: Int(before)))")
        print("    Reversed: \(data.debugStringReversed(withCursor: Int(before)))")
    }

}
