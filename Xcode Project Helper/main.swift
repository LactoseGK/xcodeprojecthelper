//
//  main.swift
//  Xcode Project Helper
//
//  Created by Geir-Kåre S. Wærp on 09/09/2018.
//  Copyright © 2018 Geir-Kåre S. Wærp. All rights reserved.
//

import Foundation

func printSeperatorLarge() {
    print("---------------------------------------------------------")
}

func printSeperatorSmall() {
    print("-------------------")
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

class LocalizationHelper {
    var databases = [LanguageDatabase]()
    var duplicates = [[String]]()

    func loadDatabases(from filepaths: [URL]) {
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
                for filepathComponent in filepath.pathComponents {
                    if filepathComponent.hasSuffix(".lproj") {
                        name = filepathComponent
                        break
                    }
                }

                databases.append(LanguageDatabase(name: name, dictionary: dictionary, duplicates: duplicates))
            } catch {
                print("ERROR: Loading database from \(filepath): \(error)")
            }
        }
    }

    func run() {
        //TODO: Better command line argument logic and error handling.
        guard CommandLine.argc == 2 else {
            print("Specify folderpath and try again.")
            return
        }
        
        let folderPath = CommandLine.arguments[1]
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let localizationFolderURL = home.appendingPathComponent(folderPath)
        guard let files = try? fm.contentsOfDirectory(at: localizationFolderURL, includingPropertiesForKeys: nil) else {
            print("ERROR: Couldn't find any localization files (.lproj)")
            return
        }

        let fileURLs = files.filter( {$0.pathExtension == "lproj"} ).map( {$0.appendingPathComponent("Localizable.strings")})
        loadDatabases(from: fileURLs)

        reportDuplicates()
        reportMissingTranslations()
        reportPossibleMissingTranslations()
    }

    func reportDuplicates() {
        print("DUPLICATE CHECK:")
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

        printSeperatorLarge()
    }

    func reportMissingTranslations() {
        print("MISSING TRANSLATION CHECK:")
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

        printSeperatorLarge()
    }

    var allDatabaseKeys: [String] {
        var keys = Set<String>()
        for database in databases {
            keys.formUnion(database.dictionary.keys)
        }

        return Array(keys)
    }

    func reportPossibleMissingTranslations() {
        print("POSSIBLE MISSING TRANSLATION CHECK:")
        for key in allDatabaseKeys {
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

        printSeperatorLarge()
    }
}

LocalizationHelper().run()
