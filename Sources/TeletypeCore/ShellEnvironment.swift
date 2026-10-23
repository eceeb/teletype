/// The environment a pane's shell is started with: the app's own environment
/// plus what a terminal has to tell its child about itself.
public enum ShellEnvironment {
    public static func make(from base: [String: String]) -> [String: String] {
        var environment = base
        environment["TERM"] = "xterm-256color"
        environment["TERM_PROGRAM"] = "Teletype"   // identify the terminal (like iTerm / Apple Terminal)
        environment["COLORTERM"] = "truecolor"     // we render 24-bit color, so say so
        return environment
    }
}
