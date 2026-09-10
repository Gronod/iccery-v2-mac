import Foundation

/// Result of evaluating one measured patch.
public struct SwatchEvaluation: Sendable, Equatable {
    public let intended: DisplayRGB
    public let measured: DisplayRGB
    public let deltaE: Double?
    public let classification: SwatchClassification

    public init(
        intended: DisplayRGB,
        measured: DisplayRGB,
        deltaE: Double?,
        classification: SwatchClassification
    ) {
        self.intended = intended
        self.measured = measured
        self.deltaE = deltaE
        self.classification = classification
    }
}

public enum SwatchClassification: String, Sendable, Equatable, CaseIterable {
    case good
    case warning
    case bad
}

/// CIEDE2000 ΔE₀₀ between two D50 Lab values.
public enum ColorDifference {

    /// Compute ΔE₀₀ using the full CIEDE2000 formula.
    public static func deltaE00(_ lab1: LabColor, _ lab2: LabColor) -> Double {
        let kL: Double = 1
        let kC: Double = 1
        let kH: Double = 1

        let c1 = sqrt(lab1.a * lab1.a + lab1.b * lab1.b)
        let c2 = sqrt(lab2.a * lab2.a + lab2.b * lab2.b)

        let cBar = (c1 + c2) / 2.0
        let cBar7 = pow(cBar, 7)
        let g = 0.5 * (1 - sqrt(cBar7 / (cBar7 + pow(25, 7))))

        let a1p = (1 + g) * lab1.a
        let a2p = (1 + g) * lab2.a

        let c1p = sqrt(a1p * a1p + lab1.b * lab1.b)
        let c2p = sqrt(a2p * a2p + lab2.b * lab2.b)

        let h1p = atan2ToDegrees(lab1.b, a1p)
        let h2p = atan2ToDegrees(lab2.b, a2p)

        let deltaLp = lab2.l - lab1.l
        let deltaCp = c2p - c1p

        var deltaHp: Double = 0
        if c1p * c2p == 0 {
            deltaHp = 0
        } else {
            let diff = h2p - h1p
            if abs(diff) <= 180 {
                deltaHp = diff
            } else if diff > 180 {
                deltaHp = diff - 360
            } else {
                deltaHp = diff + 360
            }
        }

        let deltaHp2 = 2 * sqrt(c1p * c2p) * sin(deltaHp * .pi / 360.0)

        let lBarp = (lab1.l + lab2.l) / 2.0
        let cBarp = (c1p + c2p) / 2.0

        var hBarp: Double
        if c1p * c2p == 0 {
            hBarp = h1p + h2p
        } else {
            if abs(h1p - h2p) <= 180 {
                hBarp = (h1p + h2p) / 2.0
            } else if h1p + h2p < 360 {
                hBarp = (h1p + h2p + 360) / 2.0
            } else {
                hBarp = (h1p + h2p - 360) / 2.0
            }
        }

        let t = 1
            - 0.17 * cos(deg2rad(hBarp - 30))
            + 0.24 * cos(deg2rad(2 * hBarp))
            + 0.32 * cos(deg2rad(3 * hBarp + 6))
            - 0.20 * cos(deg2rad(4 * hBarp - 63))

        let dTheta = 30 * exp(-pow((hBarp - 275) / 25, 2))
        let cBarp7 = pow(cBarp, 7)
        let rc = 2 * sqrt(cBarp7 / (cBarp7 + pow(25, 7)))

        let sl = 1 + (0.015 * pow(lBarp - 50, 2)) / sqrt(20 + pow(lBarp - 50, 2))
        let sc = 1 + 0.045 * cBarp
        let sh = 1 + 0.015 * cBarp * t

        let rt = -sin(deg2rad(2 * dTheta)) * rc

        let lTerm = deltaLp / (kL * sl)
        let cTerm = deltaCp / (kC * sc)
        let hTerm = deltaHp2 / (kH * sh)

        return sqrt(
            lTerm * lTerm
            + cTerm * cTerm
            + hTerm * hTerm
            + rt * cTerm * hTerm
        )
    }

    /// Classify a ΔE value against user thresholds.
    public static func classify(deltaE: Double, goodMax: Double, warningMax: Double) -> SwatchClassification {
        if deltaE < goodMax { return .good }
        if deltaE < warningMax { return .warning }
        return .bad
    }

    /// Evaluate a patch: compute intended/measured sRGB and ΔE if both Lab values are present.
    public static func evaluate(
        patch: ChartreadPatch,
        goodMax: Double,
        warningMax: Double
    ) -> SwatchEvaluation? {
        guard let measured = resolveLab(patch.measured) else { return nil }

        let measuredRGB = LabColorMath.labToSRGB(measured)

        if let expectedColor = patch.expected,
           let expectedLab = resolveLab(expectedColor) {
            let de = deltaE00(expectedLab, measured)
            let intendedRGB = LabColorMath.labToSRGB(expectedLab)
            return SwatchEvaluation(
                intended: intendedRGB,
                measured: measuredRGB,
                deltaE: de,
                classification: classify(deltaE: de, goodMax: goodMax, warningMax: warningMax)
            )
        } else {
            // No reference: still render measured colour, no ΔE.
            return SwatchEvaluation(
                intended: measuredRGB,
                measured: measuredRGB,
                deltaE: nil,
                classification: .good
            )
        }
    }

    /// Resolve a Lab from a `PatchColor`, computing it from XYZ when Lab is absent.
    public static func resolveLab(_ color: PatchColor) -> LabColor? {
        if let lab = color.lab { return lab }
        guard let xyz = color.xyz else { return nil }
        return LabColorMath.xyzToLab(xyz)
    }

    private static func atan2ToDegrees(_ y: Double, _ x: Double) -> Double {
        let radians = atan2(y, x)
        var degrees = radians * 180.0 / .pi
        if degrees < 0 { degrees += 360 }
        return degrees
    }

    private static func deg2rad(_ degrees: Double) -> Double {
        degrees * .pi / 180.0
    }
}
