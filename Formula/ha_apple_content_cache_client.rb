class HaAppleContentCacheClient < Formula
  desc "Home Assistant Apple Content Caching client"
  homepage "https://github.com/zacs/homebrew-ha-apple_content_cache-client"
  url "https://github.com/zacs/homebrew-ha-apple_content_cache-client/archive/refs/tags/v0.1.15.tar.gz"
  sha256 "6302197385d2d15fc79aea77c4c96f4d606b92028b77947938a819c8af999216"
  license "MIT"

  depends_on "jq"

  def install
    bin.install "bin/ha_apple_content_cache_client.sh"
    (etc/"ha-apple_content_cache-client").install ".env.example"
  end

  service do
    run [opt_bin/"ha_apple_content_cache_client.sh"]
    keep_alive true
    interval 300
    log_path var/"log/ha-apple_content_cache-client.log"
    error_log_path var/"log/ha-apple_content_cache-client.log"
    environment_variables ENV_PATH: etc/"ha-apple_content_cache-client/.env"
  end

  def caveats
    <<~EOS
      Configuration file:
        #{etc}/ha-apple_content_cache-client/.env

      Service commands:
        brew services start zacs/ha-apple_content_cache-client/ha_apple_content_cache_client
        brew services stop zacs/ha-apple_content_cache-client/ha_apple_content_cache_client

      Logs:
        tail -f ~/Library/Logs/ha-apple_content_cache-client.log
    EOS
  end

  test do
    system "#{bin}/ha_apple_content_cache_client.sh", "--help"
  end
end
