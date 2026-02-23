extension Market {
    /// Derives country from MIC code patterns
    static func countryFromMIC(_ mic: MIC) -> Country? {
        let micStr = mic.code

        switch micStr {
        // US Markets
        case "XNYS", "XNAS", "ARCX", "BATS", "IEXG", "XCBO", "XCHI", "XPHL", "XBOS",
             "XASE", "XNMS", "XNCM", "XNGS", "OTCM", "PINX", "OTCQ":
            return .us
        // UK Markets (including CBOE Europe MTFs which follow UK calendar)
        case "XLON", "XLOM", "XOFF", "AIMX", "AQUA", "CHIX", "CEUX", "BOAT", "BATE":
            return .gb
        // German Markets
        case "XETR", "XFRA", "XBER", "XHAM", "XHAN", "XDUS", "XMUN", "XSTU",
             "TGATE", "XQTX":
            return .de
        // French Markets
        case "XPAR", "ALXP", "XMLI", "XMAT":
            return .fr
        // Swiss Markets
        case "XSWX", "XVTX", "XBRN":
            return .ch
        // Swedish Markets
        case "XSTO", "FNSE", "XNGM", "SSME", "XSAT":
            return .se
        // Norwegian Markets
        case "XOSL", "XOAS", "MERK", "SPNO":
            return .no
        // Danish Markets
        case "XCSE", "FNDK", "DSME":
            return .dk
        // Finnish Markets
        case "XHEL", "FNFI":
            return .fi
        // Dutch Markets
        case "XAMS", "TNLA":
            return .nl
        // Belgian Markets
        case "XBRU", "ALXB", "TNLB", "MLXB":
            return .be
        // Spanish Markets
        case "XMAD", "BMEX", "XMCE", "XMAB":
            return .es
        // Italian Markets
        case "XMIL", "MTAA", "ETLX", "XAIM":
            return .it
        // Portuguese Markets
        case "XLIS", "ALXL", "ENXL":
            return .pt
        // Austrian Markets
        case "XWBO", "XWBV":
            return .at
        // Polish Markets
        case "XWAR", "XNCO":
            return .pl
        // Hungarian Markets
        case "XBUD":
            return .hu
        // Czech Markets
        case "XPRA":
            return .cz
        // Irish Markets
        case "XDUB", "XESM":
            return .ie
        // Greek Markets
        case "ASEX", "XATH", "ENAX":
            return .gr
        // Japanese Markets
        case "XTKS", "XJPX", "XOSE", "XNGO", "XFKA", "XSAP":
            return .jp
        // Australian Markets
        case "XASX", "XSFE", "XNEC":
            return .au
        // Canadian Markets
        case "XTSE", "XTSX", "XCNQ", "XTNX":
            return .ca
        default:
            return nil
        }
    }
}
