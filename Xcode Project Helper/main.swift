//
//  main.swift
//  Xcode Project Helper
//
//  Created by Geir-Kåre S. Wærp on 09/09/2018.
//  Copyright © 2018 Geir-Kåre S. Wærp. All rights reserved.
//

import Foundation

class CodeLine {
    let line: Int
    var text: String

    init(line: Int, text: String) {
        self.line = line
        self.text = text
    }
}

func printSeperatorLarge() {
    print("------------------------------------------------------------------------------------------------")
}

func printSeperatorMedium() {
    print("------------------------------------------------")
}

func printSeperatorSmall() {
    print("------------")
}

func getAllKeysFor(databases: [LanguageDatabase]) -> [String] {
    var keys = Set<String>()
    for database in databases {
        keys.formUnion(database.dictionary.keys)
    }

    return Array(keys)
}

class LanguageDatabase {
    var name: String
    var displayName: String { return "\"\(name)\"" }
    var dictionary: [String : CodeLine]
    var duplicates: NSCountedSet

    init(name: String, dictionary: [String : CodeLine], duplicates: NSCountedSet) {
        self.name = name
        self.dictionary = dictionary
        self.duplicates = duplicates
    }
}

class LocalizationFolder {
    var name: String
    var databases: [LanguageDatabase]

    init(name: String, databases: [LanguageDatabase]) {
        self.name = name
        self.databases = databases
    }
}

func getCodeLinesFromFileURLs(codeFileURLs: [URL]) -> [CodeLine] {
    var returningCodeLines = [CodeLine]()
    for filepath in codeFileURLs {
        do {
            let data = try String(contentsOf: filepath, encoding: .utf8)
            let codeLines = data.components(separatedBy: .newlines).enumerated().map { (index, text) in
                CodeLine(line: index + 1, text: text)
            }

            let parsedCodeLines = parse(codeLines: codeLines)
            returningCodeLines.append(contentsOf: parsedCodeLines)
        } catch {
            print("ERROR: Loading codeFile from \(filepath): \(error)")
        }
    }
    return returningCodeLines
}

extension String {
    func matchingStrings(regex: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: regex, options: []) else { return [] }
        let nsString = self as NSString
        let results  = regex.matches(in: self, options: [], range: NSMakeRange(0, nsString.length))
        return results.map { result in
            (0..<result.numberOfRanges).map { result.range(at: $0).location != NSNotFound
                ? nsString.substring(with: result.range(at: $0))
                : ""
            }
        }
    }
}

func getUsedLocalizationKeysFrom(codeFileURLs: [URL]) -> [String] {
    let codeLines = getCodeLinesFromFileURLs(codeFileURLs: codeFileURLs)
    let regex = "\"(\\w+)\"\\.localized"
    var usedLocalizationKeys = Set<String>()

    for codeLine in codeLines {
        if let key = codeLine.text.matchingStrings(regex: regex).first?[1] {
            usedLocalizationKeys.insert(key)
        }
    }

    return Array(usedLocalizationKeys)
}

func parse(codeLines: [CodeLine], maxBlockCount: Int = Int.max) -> [CodeLine] {
    var result = [CodeLine]()
    var somethingRemoved = false
    var activeBlockCommentCount = 0

    for line in codeLines {
        let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            somethingRemoved = true
            continue
        }

        guard !trimmed.hasPrefix("//") else {
            somethingRemoved = true
            continue
        }

        if trimmed.contains("/*") {
            if (activeBlockCommentCount < maxBlockCount) {
                activeBlockCommentCount += 1
                somethingRemoved = true
                continue
            }
        } else if trimmed.contains("*/") {
            if (activeBlockCommentCount > 0) {
                activeBlockCommentCount -= 1
            } else {
                print("ERROR: Negative amount of block comments!")
            }
            somethingRemoved = true
            continue
        }

        guard activeBlockCommentCount == 0 else {
            somethingRemoved = true
            continue
        }

        result.append(line)
    }

    return somethingRemoved ? parse(codeLines: result, maxBlockCount: maxBlockCount) : result
}

class LocalizationHelper {
    var localizationFolders = [LocalizationFolder]()
    var duplicates = [[String]]()

    func loadDatabases(from filepaths: [URL]) -> [LanguageDatabase] {
        var databases = [LanguageDatabase]()
        for filepath in filepaths {
            do {
                var dictionary = [String : CodeLine]()
                let duplicates = NSCountedSet()
                let data = try String(contentsOf: filepath, encoding: .utf8)
                let codeLines = data.components(separatedBy: .newlines).enumerated().map { (index, text) in
                    CodeLine(line: index + 1, text: text)
                }

                let parsedCodeLines = parse(codeLines: codeLines, maxBlockCount: 1)
                for codeLine in parsedCodeLines {
                    let line = codeLine.text
                    var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    guard !trimmed.hasPrefix("//") else { continue }
                    while trimmed.contains("//") {
                        guard let commentTrimmed = trimmed.components(separatedBy: "//").first else { break }
                        trimmed = commentTrimmed
                    }
                    trimmed = trimmed.trimmingCharacters(in: .whitespaces)
                    guard trimmed.hasSuffix(";") else {
                        if line.contains("\"") {
                            print("WARNING: We probably trimmed too much! \(line) -----> \(trimmed)")
                        }
                        continue
                    }

                    let split = trimmed.components(separatedBy: " = ")
                    guard split.count == 2 else { continue }

                    let trimSet = CharacterSet(charactersIn: ";\"")
                    let key = split[0].trimmingCharacters(in: trimSet)
                    let value = split[1].trimmingCharacters(in: trimSet)

                    duplicates.add(key)
                    dictionary[key] = CodeLine(line: codeLine.line, text: value)
                }

                var name = filepath.absoluteString
                for (index, filepathComponent) in filepath.pathComponents.enumerated() {
                    if filepathComponent.hasSuffix(".lproj") {
                        name = (index > 0) ? "\(filepath.pathComponents[index - 1])/\(filepathComponent)" : "\(filepathComponent)"
                        break
                    }
                }

                databases.append(LanguageDatabase(name: name, dictionary: dictionary, duplicates: duplicates))
            } catch {
                print("ERROR: Loading database from \(filepath): \(error)")
            }
        }

        return databases
    }

    func run() {
        //TODO: Better command line argument logic and error handling.
        //TODO TODO: Turn into non-command line. Buttons and stuff.
        guard CommandLine.argc == 2 else {
            print("Specify folderpath and try again.")
            return
        }
        
        let folderPath = CommandLine.arguments[1]
        let fm = FileManager.default
        let projectFolderURL = fm.homeDirectoryForCurrentUser.appendingPathComponent(folderPath)
        let enumerator = fm.enumerator(at: projectFolderURL, includingPropertiesForKeys: nil)
        var localizationFiles = [URL]()
        var codeFiles = [URL]()
        while let element = enumerator?.nextObject() as? URL {
            if element.pathExtension == "strings" {
                localizationFiles.append(element)
            } else if element.pathExtension == "swift" {
                codeFiles.append(element)
            }
        }

        var foldersToScan = [String : [URL]]()
        for f in localizationFiles {
            for (index, pathComponent) in f.pathComponents.enumerated() {
                if pathComponent.hasSuffix(".lproj") {
                    let dictionaryKey = (index > 0) ? "\(f.pathComponents[index - 1])" : "DefaultFolder"
                    if foldersToScan[dictionaryKey] == nil {
                        foldersToScan[dictionaryKey] = [URL]()
                    }
                    foldersToScan[dictionaryKey]?.append(f)
                    break
                }
            }
        }

        for key in foldersToScan.keys {
            guard let folderURLs = foldersToScan[key] else { continue }
            let databases = loadDatabases(from: folderURLs)
            localizationFolders.append(LocalizationFolder(name: key, databases: databases))
        }

        let usedLocalizationKeys = getUsedLocalizationKeysFrom(codeFileURLs: codeFiles)

        for folder in localizationFolders {
            print("+++++++++++++ \(folder.name) +++++++++++++")
            reportDuplicates(localizationFolder: folder)
            reportMissingTranslations(localizationFolder: folder)
            reportPossibleMissingTranslations(localizationFolder: folder)
            reportIfValueIsSameAsKey(localizationFolder: folder)
            reportIfVaryingAmountOfVariables(localizationFolder: folder)
            printSeperatorLarge()
        }

        reportUnusedKeys(localizationFolders: localizationFolders, usedKeys: usedLocalizationKeys)
        reportGhostKeysInUse(localizationFolders: localizationFolders, usedKeys: usedLocalizationKeys) //Keys that don't exist.
    }

    func reportDuplicates(localizationFolder: LocalizationFolder) {
        let databases = localizationFolder.databases
        for database in databases {
            var duplicates = [String]()
            for key in database.duplicates.allObjects {
                let count = database.duplicates.count(for: key)
                if count > 1 {
                    duplicates.append("\(key) (\(count) times)")
                }
            }

            if !duplicates.isEmpty {
                print("Duplicate keys found in \(database.displayName):")
                print(duplicates)
                printSeperatorSmall()
            }
        }

        printSeperatorMedium()
    }

    func reportMissingTranslations(localizationFolder: LocalizationFolder) {
        let databases = localizationFolder.databases
        for database in databases {
            let allKeys = Set(getAllKeysFor(databases: localizationFolder.databases))
            let myKeys = Set(getAllKeysFor(databases: [database]))
            let diff = allKeys.subtracting(myKeys)

            var missingKeys = [String]()
            for key in diff {
                var missingFromDatabases = [String]()
                for db in databases {
                    if db.dictionary[key] != nil {
                        missingFromDatabases.append(db.name)
                    }
                }

                missingKeys.append("\"\(key)\" -- exists in: \(missingFromDatabases)")
            }

            if !missingKeys.isEmpty {
                print("\(database.name) missing keys from other databases:")
                for str in missingKeys {
                    print(str)
                }
                printSeperatorSmall()
            }
        }

        printSeperatorMedium()
    }

    func reportPossibleMissingTranslations(localizationFolder: LocalizationFolder) {
        let databases = localizationFolder.databases
        for key in getAllKeysFor(databases: databases) {
            let countedSet = NSCountedSet()
            for database in databases {
                if let value = database.dictionary[key]?.text {
                    countedSet.add(value)
                }
            }

            for value in countedSet.allObjects as! [String] {
                if countedSet.count(for: value) > 1 {
                    var matchingDatabaseNames = [String]()
                    for database in databases {
                        if database.dictionary[key]?.text == value {
                            matchingDatabaseNames.append(database.name)
                        }
                    }

                    print("\"\(key)\" has the same translation in \(matchingDatabaseNames): \"\(value)\"")
                    printSeperatorSmall()
                }
            }
        }

        printSeperatorMedium()
    }

    func reportIfValueIsSameAsKey(localizationFolder: LocalizationFolder) {
        let databases = localizationFolder.databases
        for database in databases {
            var warnings = [String]()
            database.dictionary.forEach { (key, value) in
                if key == value.text {
                    warnings.append("\(key)")
                }
            }

            if !warnings.isEmpty {
                print("\(database.displayName) has key(s) with translation = key. Intentional?")
                print(warnings)
            }
        }

        printSeperatorMedium()
    }

    func reportIfVaryingAmountOfVariables(localizationFolder: LocalizationFolder) {
        let databases = localizationFolder.databases
        guard !databases.isEmpty else { return }

        let allKeys = getAllKeysFor(databases: databases)
        for key in allKeys {
            var numVariables = [String : Int]()
            for database in databases {
                let variableCount: Int
                if let value = database.dictionary[key]?.text {
                    if value.contains("%@") {
                        let stripped = value.replacingOccurrences(of: "%@", with: "")
                        variableCount = (value.count - stripped.count) / 2
                    } else {
                        variableCount = 0
                    }
                } else {
                    variableCount = 0
                }

                numVariables[database.displayName] = variableCount
            }

            for database in databases {
                let comparison = numVariables[databases.first!.displayName]!
                let current = numVariables[database.displayName]!
                if current != comparison {
                    print("\"\(key)\" -- Mismatched amount of variables -- \(databases.first!.displayName) = \(comparison), \(database.displayName) = \(current)")
                }
            }
        }
    }

    func reportUnusedKeys(localizationFolders: [LocalizationFolder], usedKeys: [String]) {
        var allKeys = Set<String>()
        for folder in localizationFolders {
            allKeys.formUnion(getAllKeysFor(databases: folder.databases))
        }

        let usedKeySet = Set<String>(usedKeys)
        var unusedKeys = [String]()
        for key in allKeys {
            if !usedKeySet.contains(key) {
                unusedKeys.append(key)
            }
        }

        if !unusedKeys.isEmpty {
            print("Unused keys found:")
            print(unusedKeys)
        }
    }

    func reportGhostKeysInUse(localizationFolders: [LocalizationFolder], usedKeys: [String]) {
        var allKeys = Set<String>()
        for folder in localizationFolders {
            allKeys.formUnion(getAllKeysFor(databases: folder.databases))
        }

        var ghostKeys = [String]()
        for usedKey in usedKeys {
            if !allKeys.contains(usedKey) {
                ghostKeys.append(usedKey)
            }
        }

        if !ghostKeys.isEmpty {
            print("Keys used that were not found in any localization folder:")
            print(ghostKeys)
        }
    }
}

LocalizationHelper().run()
