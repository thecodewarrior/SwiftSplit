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
    var autoSplitterInfo: RmaPointer? = nil
    var extendedInfo: RmaPointer? = nil
    let target: MemscanTarget
    let process: RmaProcess

    init(pid: pid_t) throws {
        self.pid = pid
        target = try MemscanTarget(pid: pid)
        process = RmaProcess(target: target, filter: MemscanFilter(startAddress: 0, endAddress: 0x0000001000000000))
    }

    func findHeader() throws {
        print("Scanning for the AutoSplitterData object header")

        extendedInfo = try process.findPointer(by: "11efbeadde11")

        if CelesteScanner.canImmediatelyConnect(pid: pid) {
            headerInfo = CelesteScanner.lastHeader
            try? debugPointers()
            return
        }

        autoSplitterInfo = try process.findPointer(by:
            "7f00000000000000000000????????????????ffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
            )?.offset(by: -5)
        if let info = autoSplitterInfo {
            headerInfo = HeaderInfo(pid: pid, signatureData: try info.read(bytes: 16))
            CelesteScanner.lastHeader = headerInfo
        }

    }

    func readExtended() throws -> ExtendedAutoSplitterData? {
//        if guard let extendedInfo = extendedInfo else {
//            return nil
//        }
//        let buf = try target.read(at: extendedPointer, count: )
//        return ExtendedAutoSplitterData(from: extendedInfo)
        return nil
    }

    func getInfo() throws -> AutoSplitterInfo? {
        guard let header = self.headerInfo else { return nil }
        if try autoSplitterInfo?.read(bytes: 16) != header.signatureData {
            autoSplitterInfo = try process.findPointer(by: MemscanSignature(from: header.signatureData))
        }
        guard let info = autoSplitterInfo else { return nil }
        return try AutoSplitterInfo(from: try AutoSplitterData(from: info))
    }

    /**
     Run a scan for the level strings, printing the memory of every match. Useful for figuring out the memory layout
     */
    func debugPointers() throws {

//        print("Running a pointer debug")
//        guard let signature = headerSignature else {
//            print("  There is no header signature. Please open the AUTOSPLIT save and scan for the header.")
//            pointer = 0
//            return
//        }
//
//        let scanner = MemscanScanner(target: target, signature: signature, filter: filter)
//        while let match = try scanner.next() {
//            print(String(format: "Object @ %016llx", match.address))
//
//            let vTable_ptr = try readPointer(from: match.address, offset: 0)
//            print(String(format: "VTable @ %016llx", vTable_ptr))
//
////            try debugMemoryAround(vTable_ptr, before: 0, after: 64)
//
//            let monoClass_ptr = try readPointer(from: vTable_ptr, offset: 0)
//            print(String(format: "MonoClass @ %016llx", monoClass_ptr))
//
////            try debugMemoryAround(monoClass_ptr, before: 0, after: 64)
//
//            let name_ptr = try readPointer(from: monoClass_ptr, offset: 8)
//            print(String(format: "MonoClass.name @ %016llx", name_ptr))
//            try debugMemoryAround(name_ptr, before: 0, after: 128)
//
//        }
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

    static var lastHeader: HeaderInfo? {
        get {
            if let data = UserDefaults.standard.value(forKey: "lastHeader") as? Data,
                let lastHeader = try? PropertyListDecoder().decode(HeaderInfo.self, from: data) {
                return lastHeader
            }
            return nil
        }
        set(value) {
            if let value = value {
                UserDefaults.standard.set(try? PropertyListEncoder().encode(value), forKey: "lastHeader")
            } else {
                UserDefaults.standard.removeObject(forKey: "lastHeader")
            }
        }
    }

    static func canImmediatelyConnect(pid: pid_t) -> Bool {
        return CelesteScanner.lastHeader?.pid == pid
    }
}

struct HeaderInfo: Codable {
    var pid: pid_t
    var signatureData: [UInt8]

    init(pid: pid_t, signatureData: [UInt8]) {
        self.pid = pid
        self.signatureData = signatureData
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
struct AutoSplitterData {
    var header: UInt64
    var monoSync: UInt64

    var chapter: Int32
    var mode: Int32
    var level: RmaPointer
    var timerActive: UInt8
    var chapterStarted: UInt8
    var chapterComplete: UInt8
    var chapterTime: Int64
    var chapterStrawberries: Int32
    var chapterCassette: UInt8
    var chapterHeart: UInt8
    var fileTime: Int64
    var fileStrawberries: Int32
    var fileCassettes: Int32
    var fileHearts: Int32

    init(from pointer: RmaPointer) throws {
        let preload = try pointer.preload(size: 80)
        header = preload.value(at: 0)
        monoSync = preload.value(at: 8)
        level = preload.value(at: 16)
        chapter = preload.value(at: 24)
        mode = preload.value(at: 28)
        timerActive = preload.value(at: 32)
        chapterStarted = preload.value(at: 33)
        chapterComplete = preload.value(at: 34)
        chapterTime = preload.value(at: 40)
        chapterStrawberries = preload.value(at: 48)
        chapterCassette = preload.value(at: 52)
        chapterHeart = preload.value(at: 53)
        fileTime = preload.value(at: 56)
        fileStrawberries = preload.value(at: 64)
        fileCassettes = preload.value(at: 68)
        fileHearts = preload.value(at: 72)
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

    init(from data: AutoSplitterData) throws {
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
        self.level = try Mono.readString(at: data.level)
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

struct ExtendedAutoSplitterData {
    var madelineX: Float = 0.0
    var madelineY: Float = 0.0

    init() {}

    init(from pointer: RmaPointer) throws {
        madelineX = try pointer.value(at: 0)
        madelineY = try pointer.value(at: 4)
    }
}

