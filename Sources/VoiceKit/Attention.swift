import Foundation
import HiveCore

/// Which running sessions need the user, with the same rule as Hive's notifications (status rank 0).
public enum Attention {
    public static func needs(_ sessions: [Session]) -> [String: AttentionTracker.Need] {
        var m: [String: AttentionTracker.Need] = [:]
        for s in sessions where s.alive && m[s.name] == nil {
            let st = SessionStatus(s)
            guard st.rank == 0 else { continue }
            m[s.name] = AttentionTracker.Need(reason: st.reason ?? st.label, confirmAfter: st.waitsAtStart ? 3 : 0)
        }
        return m
    }
}
