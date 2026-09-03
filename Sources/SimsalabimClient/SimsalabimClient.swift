// Linking this module activates all three simulator bridges. The exported
// imports also make their optional fixture APIs available through one import.
#if os(iOS)
@_exported import CAMouflage
@_exported import ImpossiBLE
@_exported import NFCromancer
#endif
