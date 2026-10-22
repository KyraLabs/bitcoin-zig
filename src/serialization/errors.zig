pub const DecodeError = error{
    EndOfStream,
    NonCanonicalCompactSize,
    SizeTooLarge,
    ValueOutOfRange,
};
