// The start of every probe that runs the core (probe_start.py adds this file and its flags): the Mac
// implementations of the core's joints first, the way the app gives them at launch (MacPlatformServices), then the
// probe's own main, renamed oortProbeMain. A revision from before the joints (OORT_NO_JOINTS) only starts the probe.
@_silgen_name("oortProbeMain")
func oortProbeMain(_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32

@_cdecl("oortProbeStart")
func oortProbeStart(_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32 {
    #if !OORT_NO_JOINTS
    MacPlatformServices.register()
    #endif
    return oortProbeMain(argc, argv)
}
