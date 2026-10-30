package dev.nirang.client.vpn

/** Converts cumulative native counters to the ledger's reset-on-read format. */
internal class CoreTrafficDelta {
    private var up=0L
    private var down=0L
    @Synchronized fun sample(currentUp:Long,currentDown:Long):String? {
        if(currentUp < 0 || currentDown < 0) return null
        val previousUp=up;val previousDown=down
        up=currentUp;down=currentDown
        if(currentUp < previousUp || currentDown < previousDown) return null
        return "proxy,uplink,${currentUp-previousUp};proxy,downlink,${currentDown-previousDown}"
    }
}
