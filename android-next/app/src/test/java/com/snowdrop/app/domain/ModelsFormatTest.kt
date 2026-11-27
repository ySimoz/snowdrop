package com.snowdrop.app.domain

import org.junit.Assert.assertEquals
import org.junit.Test

class ModelsFormatTest {

    @Test
    fun peerDisplayNameFallsBackCleanly() {
        assertEquals("Studio Mac", PeerItem("1", "host", "Studio Mac", "dns").displayName)
        assertEquals("host", PeerItem("1", "host", "", "dns").displayName)
        assertEquals("dns", PeerItem("1", "", "", "dns").displayName)
        assertEquals("node-1", PeerItem("node-1", "", "", "").displayName)
    }

    @Test
    fun transferProgressClampsCleanly() {
        val zero = TransferItem("t1", "a.bin", "Mac", TransferDirection.OUTGOING, bytesTransferred = 10L, totalBytes = 0L)
        assertEquals(0f, zero.progress, 0.0001f)

        val over = TransferItem("t2", "b.bin", "Mac", TransferDirection.OUTGOING, bytesTransferred = 200L, totalBytes = 100L)
        assertEquals(1f, over.progress, 0.0001f)
    }

    @Test
    fun snowdropFormatFormatsBytesSpeedAndEta() {
        assertEquals("0 B", SnowdropFormat.bytes(0L))
        assertEquals("512 B", SnowdropFormat.bytes(512L))
        assertEquals("2 KB", SnowdropFormat.bytes(2048L))
        assertEquals("1.5 MB", SnowdropFormat.bytes(1_572_864L))
        assertEquals("2.00 GB", SnowdropFormat.bytes(2L * 1024L * 1024L * 1024L))

        assertEquals("", SnowdropFormat.speed(0.0))
        assertEquals("1.0 MB/s", SnowdropFormat.speed(1_048_576.0))

        assertEquals("", SnowdropFormat.eta(0.2))
        assertEquals("45s", SnowdropFormat.eta(45.0))
        assertEquals("2m 5s", SnowdropFormat.eta(125.0))
    }
}
