import SwiftData

/// Vane's first explicit schema checkpoint. Future model changes must introduce a
/// new version and a reviewed lightweight or custom migration stage here.
enum VaneSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static let models: [any PersistentModel.Type] = [
        WeatherProfile.self,
        WeatherCheckIn.self,
        SavedPlace.self,
    ]
}

enum VaneMigrationPlan: SchemaMigrationPlan {
    static let schemas: [any VersionedSchema.Type] = [VaneSchemaV1.self]
    static let stages: [MigrationStage] = []
}
