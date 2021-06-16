//
//  CelesteMemory.swift
//  SwiftSplit
//
//  Created by Pierce Corcoran on 11/19/20.
//  Copyright © 2020 Pierce Corcoran. All rights reserved.
//

import Foundation

/**
 Scans for and interprets the Celeste AutoSplitterInfo
 */
class CelesteScanner {
    var enableDebugPrinting: Bool = false
    
    var pid: pid_t
    var headerInfo: HeaderInfo? = nil {
        didSet {
            if let info = headerInfo {
                self.headerSignature = MemscanSignature(from: info.signatureData)
            } else {
                self.headerSignature = nil
            }
        }
    }
    var headerSignature: MemscanSignature? = nil
    var pointer: vm_address_t = 0
    let target: MemscanTarget
    let filter: MemscanFilter

    init(pid: pid_t) throws {
        self.pid = pid
        target = try MemscanTarget(pid: pid)
        filter = MemscanFilter(startAddress: 0, endAddress: 0x0000700000000000)
    }
    
    func findHeader() throws {
        print("Scanning for the AutoSplitterData object header")
        
        if let data = UserDefaults.standard.value(forKey: "lastHeader") as? Data,
            let lastHeader = try? PropertyListDecoder().decode(HeaderInfo.self, from: data) {
            if lastHeader.pid == pid {
                print("Found existing header for pid \(pid)")
                headerInfo = lastHeader
                return
            }
        }

        let bigboisignature = MemscanSignature(parsing:
            "7f00000000000000000000????????????????ffffffffffffffff000000000000000000000" +
            "000000000000000000000000000000000000000000000000000000000000000000000000000"
        )
        let scanner = MemscanScanner(target: target, signature: bigboisignature, filter: filter)
        while let match = try scanner.next() {
            let address = match.address - 5
            print(String(format: "  Found a candiate object at %016llx", address))
            let data = try target.read(at: address, count: 16)
            let info = HeaderInfo(pid: pid, signatureData: Array(data.buffer.bindMemory(to: UInt8.self)), header: try readData(at: address).header)
            headerInfo = info
            UserDefaults.standard.set(try? PropertyListEncoder().encode(info), forKey: "lastHeader")
            return
        }
    }
    
    func readData(at pointer: vm_address_t) throws -> AutoSplitterData {
        let buf = try target.read(at: pointer, count: AutoSplitterData.STRUCT_SIZE)
        var data = AutoSplitterData(from: buf.buffer.baseAddress!)
        data.location = pointer
        return data
    }
    
    func findData() throws {
        print("Searching for the AutoSplitterInfo instance")
        guard let signature = headerSignature else {
            print("  There is no header signature. Please launch the game fresh and scan for the header.")
            pointer = 0
            return
        }

        let scanner = MemscanScanner(target: target, signature: signature, filter: filter)
        
        if let match = try scanner.next() {
            self.pointer = match.address
            print(String(format: "  Found the instance at %llx", match.address))
        } else {
            pointer = 0
        }
    }
    
    func getInfo() throws -> AutoSplitterInfo? {
        if pointer == 0 { try findData() }
        if pointer == 0 { return nil }
        guard let headerInfo = self.headerInfo else { return nil }
        var data = try readData(at: pointer)
        if data.header != headerInfo.header || data.headerPad != 0 {
            try findData()
            if pointer == 0 { return nil }
            data = try readData(at: pointer)
        }
        return try AutoSplitterInfo(from: data, in: target)
    }
    
    /**
     Run a scan for the signature, printing the memory of every match. Useful for figuring out the memory layout
     */
    func debugScan() throws {
        print("Running a debug scan")
        let fileTimeSignature = MemscanSignature(parsing: "11addeefbeadde11")

        let scanner = MemscanScanner(target: target, signature: fileTimeSignature, filter: filter)
        while let match = try scanner.next() {
            print(String(format:"  Found a candidate at %llx", match.address))
            try debugMemoryAround(match.address, before: 64, after: 64)
        }
    }
    
    /**
     Run a scan for the level strings, printing the memory of every match. Useful for figuring out the memory layout
     */
    func debugPointers() throws {
        
        print("Running a pointer debug")
        guard let signature = headerSignature else {
            print("  There is no header signature. Please open the AUTOSPLIT save and scan for the header.")
            pointer = 0
            return
        }

        let scanner = MemscanScanner(target: target, signature: signature, filter: filter)
        while let match = try scanner.next() {
            print(String(format: "  Found an instance at %016llx", match.address))
            let data = try readData(at: match.address)
            print(String(format: "    Level string points to %016llx", data.levelPointer))
            try debugMemoryAround(data.levelPointer, before: 16, after: 64)
            
            let vTable = try readPointer(from: match.address, offset: 0)
            print(String(format: "    Object header points to %016llx", vTable))
            try debugMemoryAround(vTable, before: 0, after: 64)

            let classData = try readPointer(from: vTable, offset: 24)
            print(String(format: "    Static class data at %016llx", classData))
            try debugMemoryAround(classData, before: 0, after: 64)

            let monoClass = try readPointer(from: vTable, offset: 0)
            print(String(format: "    MonoClass at %016llx", monoClass))
            try debugMemoryAround(monoClass, before: 0, after: 64)
            
            let monoClassName = try readPointer(from: monoClass, offset: 8)
            print(String(format: "    MonoClass name at %016llx", monoClassName))
            try debugMemoryAround(monoClassName, before: 0, after: 64)
            
        }
    }
    
    func readPointer(from address: vm_address_t, offset: vm_offset_t) throws -> vm_address_t {
        let data = try target.read(at: address + offset, count: 8)
        return data.buffer.bindMemory(to: vm_address_t.self)[0]
    }
    
    func debugMemoryAround(_ address: vm_address_t, before: vm_offset_t, after: vm_offset_t) throws {
        let data = try target.read(at: address - before, count: before + after)
        print("    Forward: \(data.debugString(withCursor: Int(before)))")
        print("    Reversed: \(data.debugStringReversed(withCursor: Int(before)))")
    }
}

struct HeaderInfo: Codable {
    var pid: pid_t
    var signatureData: [UInt8]
    var header: UInt64

    init(pid: pid_t, signatureData: [UInt8], header: UInt64) {
        self.pid = pid
        self.signatureData = signatureData
        self.header = header
    }
}

/**
 A representation of the C# AutoSplitterInfo memory.
 
 The C# AutoSplitterInfo layout is as follows::
 ```
 Placeholders:
 {
     Chapter = 0x1faaaaf1,
     Mode = 0x1fbbbbf1,
     Level = rand.Next().ToString(),
     TimerActive = true,
     ChapterStarted = true,
     ChapterComplete = true,
     ChapterTime = 0x11aabbccddeeff11,
     ChapterStrawberries = 0x1fccccf1,
     ChapterCassette = true,
     ChapterHeart = true,
     FileTime = 0x11deadbeefdead11,
     FileStrawberries = 0x1fddddf1,
     FileCassettes = 0x1feeeef1,
     FileHearts = 0x1ffffff1
 }
 ```
 
 ```
 10b212968c7f0000 00000000 00000000 b83c632d01000000 f1aaaa1f f1bbbb1f 01010100 00000000 - placeholders
 --------######## -------- ######## --------######## -------- ######## -------- ########
 0       4        8        12       16      20       24       28       32       36
 10e28b84a07f0000 00000000 00000000 b009150f01000000 ffffffff ffffffff 00000000 00000000 - Fresh launch state
 
 11ffeeddccbbaa11 f1cccc1f 01010000 11addeefbeadde11 f1dddd1f f1eeee1f f1ffff1f 00000000 - placeholders
 --------######## -------- ######## --------######## -------- ######## -------- ########
 40      44       48       52       56      60       64       68       72       76
 0000000000000000 00000000 00000000 0000000000000000 00000000 00000000 00000000 00000000 - Fresh launch state
 ```
 */
struct AutoSplitterData: Equatable {
    var location: vm_address_t = 0
    var header: UInt64 = 0
    var headerPad: UInt64 = 0
    
    var chapter: Int32 = 0
    var mode: Int32 = 0
    var levelPointer: vm_address_t = 0
    var timerActive: UInt8 = 0
    var chapterStarted: UInt8 = 0
    var chapterComplete: UInt8 = 0
    var chapterTime: Int64 = 0
    var chapterStrawberries: Int32 = 0
    var chapterCassette: UInt8 = 0
    var chapterHeart: UInt8 = 0
    var fileTime: Int64 = 0
    var fileStrawberries: Int32 = 0
    var fileCassettes: Int32 = 0
    var fileHearts: Int32 = 0

    init() {}
    
    init(from pointer: UnsafeRawPointer) {
        header = pointer.load(fromByteOffset: 0, as: UInt64.self)
        headerPad = pointer.load(fromByteOffset: 8, as: UInt64.self)
        levelPointer = pointer.load(fromByteOffset: 16, as: vm_address_t.self)
        chapter = pointer.load(fromByteOffset: 24, as: Int32.self)
        mode = pointer.load(fromByteOffset: 28, as: Int32.self)
        timerActive = pointer.load(fromByteOffset: 32, as: UInt8.self)
        chapterStarted = pointer.load(fromByteOffset: 33, as: UInt8.self)
        chapterComplete = pointer.load(fromByteOffset: 34, as: UInt8.self)
        chapterTime = pointer.load(fromByteOffset: 40, as: Int64.self)
        chapterStrawberries = pointer.load(fromByteOffset: 48, as: Int32.self)
        chapterCassette = pointer.load(fromByteOffset: 52, as: UInt8.self)
        chapterHeart = pointer.load(fromByteOffset: 53, as: UInt8.self)
        fileTime = pointer.load(fromByteOffset: 56, as: Int64.self)
        fileStrawberries = pointer.load(fromByteOffset: 64, as: Int32.self)
        fileCassettes = pointer.load(fromByteOffset: 68, as: Int32.self)
        fileHearts = pointer.load(fromByteOffset: 72, as: Int32.self)
    }
    
    static let FILE_TIME_OFFSET: vm_offset_t = 56
    static let STRUCT_SIZE: vm_offset_t = 80
    
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
    static func parseCSharpString(at address: vm_address_t, target: MemscanTarget) throws -> String {
        let lengthData = try target.read(at: address + 16, count: 4)
        let length = lengthData.buffer.load(as: Int32.self)
        
        let stringData = try target.read(at: address + 20, count: vm_offset_t(length) * 2)
        return String(utf16CodeUnits: stringData.buffer.bindMemory(to: unichar.self).baseAddress!, count: Int(length))
    }
}

enum ChapterMode : Equatable {
    case Menu
    case Normal
    case BSide
    case CSide
    case Other(value: Int)
}

/**
 A swift representation of the C# AutoSplitterInfo
 */
class AutoSplitterInfo {
    let data: AutoSplitterData
    
    let chapter: Int
    let mode: ChapterMode
    let level: String
    let timerActive: Bool
    let chapterStarted: Bool
    let chapterComplete: Bool
    let chapterTime: Double
    let chapterStrawberries: Int
    let chapterCassette: Bool
    let chapterHeart: Bool
    let fileTime: Double
    let fileStrawberries: Int
    let fileCassettes: Int
    let fileHearts: Int
    
    init() {
        self.data = AutoSplitterData()
        
        self.chapter = 0
        self.mode = .Normal
        self.level = ""
        self.timerActive = false
        self.chapterStarted = false
        self.chapterComplete = false
        self.chapterTime = 0
        self.chapterStrawberries = 0
        self.chapterCassette = false
        self.chapterHeart = false
        self.fileTime = 0
        self.fileStrawberries = 0
        self.fileCassettes = 0
        self.fileHearts = 0
    }
    
    init(from data: AutoSplitterData, in target: MemscanTarget) throws {
        self.data = data
        
        self.chapter = Int(data.chapter)
        switch data.mode {
        case -1:
            self.mode = .Menu
        case 0:
            self.mode = .Normal
        case 1:
            self.mode = .BSide
        case 2:
            self.mode = .CSide
        default:
            self.mode = .Other(value: Int(data.mode))
        }
        self.level = try AutoSplitterData.parseCSharpString(at: data.levelPointer, target: target)
        self.timerActive = data.timerActive != 0
        self.chapterStarted = data.chapterStarted != 0
        self.chapterComplete = data.chapterComplete != 0
        self.chapterTime = Double(data.chapterTime) / 10_000_000.0
        self.chapterStrawberries = Int(data.chapterStrawberries)
        self.chapterCassette = data.chapterCassette != 0
        self.chapterHeart = data.chapterHeart != 0
        self.fileTime = Double(data.fileTime) / 10_000_000.0
        self.fileStrawberries = Int(data.fileStrawberries)
        self.fileCassettes = Int(data.fileCassettes)
        self.fileHearts = Int(data.fileHearts)
    }
}
