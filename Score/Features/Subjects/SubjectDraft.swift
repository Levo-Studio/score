import Foundation
import SwiftData

/// Der Entwurf eines Fachs, an dem der Editor arbeitet.
///
/// Geschrieben wird erst beim Sichern. Beim Bearbeiten wäre das Gegenteil
/// verlockend — direkt am `@Bindable` hängen —, aber dann hätte ein abgebrochener
/// Wechsel des Fachtyps den Schnitt bereits verändert: Block I hängt am Typ.
///
/// iPhone und iPad zeigen dieselben Felder in verschiedenen Anordnungen. Der
/// Entwurf und der Weg ins Datenmodell liegen deshalb hier, nicht in einer der
/// beiden Ansichten.
struct SubjectDraft {

    var name: String
    var abbreviation: String
    var colorValue: Int
    var kind: SubjectKind
    var activeSemesters: Set<Int>
    var writtenShare: Int

    init(subject: Subject?) {
        name = subject?.name ?? ""
        abbreviation = subject?.abbreviation ?? ""
        colorValue = subject?.colorValue ?? Int(ScorePalette.subjectColorValues[0])
        kind = subject?.kind ?? .basisfach
        activeSemesters = Set(subject?.activeSemesters ?? Semester.allIndices)
        writtenShare = subject?.writtenShare ?? 50
    }

    // MARK: - Ändern

    /// Übernimmt Name, Kürzel, Farbe und Typ aus einer Katalogvorlage.
    mutating func apply(_ template: SubjectCatalog.Template) {
        name = template.name
        abbreviation = template.abbreviation
        colorValue = template.colorValue
        kind = template.defaultKind
    }

    /// Das letzte belegte Halbjahr lässt sich nicht abwählen — ein Fach ohne
    /// jedes Halbjahr wäre ein Datensatz, der nirgends mehr auftaucht.
    mutating func toggleSemester(_ index: Int) {
        if activeSemesters.contains(index) {
            guard activeSemesters.count > 1 else { return }
            activeSemesters.remove(index)
        } else {
            activeSemesters.insert(index)
        }
    }

    // MARK: - Vorschläge

    /// Vorschläge für das Kürzel, abgeleitet aus dem Namen.
    ///
    /// Die Design-Datei zeigt eine feste Liste — die stammt aus dem Prototyp und
    /// passt zu keinem selbst getippten Fach. Sinnvoller sind Vorschläge, die aus
    /// dem stehen, was der Nutzer gerade eingetippt hat.
    var abbreviationSuggestions: [String] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var suggestions: [String] = []

        if !abbreviation.isEmpty { suggestions.append(abbreviation) }
        if let template = SubjectCatalog.template(named: trimmed) {
            suggestions.append(template.abbreviation)
        }

        let initials = trimmed.split(separator: " ").compactMap(\.first).map(String.init).joined()
        if initials.count > 1 { suggestions.append(initials) }

        for length in 1...3 where trimmed.count >= length {
            suggestions.append(String(trimmed.prefix(length)))
        }

        var seen = Set<String>()
        return suggestions.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    // MARK: - Sichern

    /// Schreibt den Entwurf ins Modell — in ein bestehendes Fach oder in ein neues.
    ///
    /// - Parameters:
    ///   - subject: Das zu ändernde Fach, oder `nil` für ein neues.
    ///   - existingSubjects: Alle vorhandenen Fächer, für die Sortierposition.
    /// - Returns: Das gesicherte Fach.
    @discardableResult
    func save(
        to subject: Subject?,
        in context: ModelContext,
        existingSubjects: [Subject]
    ) -> Subject {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? String.scoreLocalized("Neues Fach") : trimmed
        let finalAbbreviation = abbreviation.isEmpty ? String(finalName.prefix(2)) : abbreviation
        let semesters = activeSemesters.sorted()

        if let subject {
            subject.name = finalName
            subject.abbreviation = finalAbbreviation
            subject.colorValue = colorValue
            subject.kind = kind
            subject.activeSemesters = semesters
            subject.writtenShare = writtenShare
            return subject
        }

        let subject = Subject(
            name: finalName,
            abbreviation: finalAbbreviation,
            colorValue: colorValue,
            kind: kind,
            isCustom: SubjectCatalog.template(named: finalName) == nil,
            writtenShare: writtenShare,
            activeSemesters: semesters,
            sortIndex: (existingSubjects.map(\.sortIndex).max() ?? -1) + 1
        )
        context.insert(subject)

        // Die vier Halbjahre entstehen zusammen mit dem Fach. Sonst müsste jede
        // Ansicht damit rechnen, dass ein Halbjahr fehlt.
        for index in Semester.allIndices {
            let semester = SemesterResult(index: index)
            semester.subject = subject
            context.insert(semester)
        }

        return subject
    }
}
