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
    
    /**
     Parse a C# string object
     
     Memory layout:
     ```
     "NUM:0"
     ```
     ```
     header                        length "N    U    M    :    0   "
     a8cd0054c57f0000 0000000000000000 05000000 4e00 5500 4d00 3a00 3000
     0                8                16       20
     ```
     */
    static func readString(at pointer: RmaPointer) throws -> String? {
        if pointer.address == 0 {
            return nil
        }
        let length: Int32 = try pointer.value(at: 16)
        let stringData = try pointer.raw(at: 20, count: vm_offset_t(length) * 2)
        return String(utf16CodeUnits: stringData.buffer.bindMemory(to: unichar.self).baseAddress!, count: Int(length))
    }
    
    static func debugMemory(around pointer: RmaPointer, before: vm_offset_t, after: vm_offset_t) throws {
        let data = try pointer.raw(at: -Int(before), count: before + after)
        print("    Forward: \(data.debugString(withCursor: Int(before)))")
        print("    Reversed: \(data.debugStringReversed(withCursor: Int(before)))")
    }

}
