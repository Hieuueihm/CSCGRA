"""Real-core AXI payload DMA integration under Vivado XSim."""
import unittest

from verification.v4 import test_host_axi_rtl as host_axi


class HostDmaRtlTests(host_axi.HostAxiRtlTests):
    DMA = True

    def test_dma_upload_and_download(self):
        self.assertIn("DMA_UPLOAD_PASS", self.ran.stdout)
        self.assertIn("DMA_DOWNLOAD_PASS", self.ran.stdout)


if __name__ == "__main__":
    unittest.main()
