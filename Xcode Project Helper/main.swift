//
//  main.swift
//  Xcode Project Helper
//
//  Created by Geir-Kåre S. Wærp on 09/09/2018.
//  Copyright © 2018 Geir-Kåre S. Wærp. All rights reserved.
//

import Foundation

func printSeperatorLarge() {
    print("------------------------------------------------------------------------------------------------")
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
    var dictionary: [String : String]
    var duplicates: NSCountedSet

    init(name: String, dictionary: [String : String], duplicates: NSCountedSet) {
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

class LocalizationHelper {
    var localizationFolders = [LocalizationFolder]()
    var duplicates = [[String]]()

    func loadDatabases(from filepaths: [URL]) -> [LanguageDatabase] {
        var databases = [LanguageDatabase]()
        for filepath in filepaths {
            do {
                var dictionary = [String : String]()
                let duplicates = NSCountedSet()
                let data = try String(contentsOf: filepath, encoding: .utf8)
                let lines = data.components(separatedBy: .newlines)
                for line in lines {
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
                    //TODO: Handle (or at least detect) block comments.

                    let split = trimmed.components(separatedBy: " = ")
                    guard split.count == 2 else { continue }

                    let trimSet = CharacterSet(charactersIn: ";\"")
                    let key = split[0].trimmingCharacters(in: trimSet)
                    let value = split[1].trimmingCharacters(in: trimSet)

                    duplicates.add(key)
                    dictionary[key] = value
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
        while let element = enumerator?.nextObject() as? URL {
            if element.pathExtension == "strings" {
                localizationFiles.append(element)
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

        for folder in localizationFolders {
            print("+++++++++++++ \(folder.name) +++++++++++++")
            reportDuplicates(localizationFolder: folder)
            reportMissingTranslations(localizationFolder: folder)
            reportPossibleMissingTranslations(localizationFolder: folder)
            printSeperatorLarge()
        }
    }

    func reportDuplicates(localizationFolder: LocalizationFolder) {
        print("DUPLICATE CHECK:")
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
        print("MISSING TRANSLATION CHECK:")
        let databases = localizationFolder.databases
        for databaseA in databases {
            for databaseB in databases {
                guard databaseA !== databaseB else { continue }

                var missingKeys = [String]()
                for key in databaseA.dictionary.keys {
                    if databaseB.dictionary[key] == nil {
                        missingKeys.append(key)
                    }
                }

                if !missingKeys.isEmpty {
                    print("Keys from \(databaseA.displayName) missing from \(databaseB.displayName):")
                    print(missingKeys)
                    printSeperatorSmall()
                }
            }
        }

        printSeperatorMedium()
    }

    func reportPossibleMissingTranslations(localizationFolder: LocalizationFolder) {
        print("POSSIBLE MISSING TRANSLATION CHECK:")
        let databases = localizationFolder.databases
        for key in getAllKeysFor(databases: databases) {
            let countedSet = NSCountedSet()
            for database in databases {
                if let value = database.dictionary[key] {
                    countedSet.add(value)
                }
            }

            for value in countedSet.allObjects as! [String] {
                if countedSet.count(for: value) > 1 {
                    var matchingDatabaseNames = [String]()
                    for database in databases {
                        if database.dictionary[key] == value {
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
}

LocalizationHelper().run()
