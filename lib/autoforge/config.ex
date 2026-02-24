defmodule Autoforge.Config do
  use Ash.Domain, otp_app: :autoforge

  resources do
    resource Autoforge.Config.TailscaleConfig
  end
end
