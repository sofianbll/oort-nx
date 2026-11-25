import Foundation

public enum CatalogScanError: Error, Equatable { case sourceDisabled, staleScan, wrongSourceRoot, invalidSnapshot }
