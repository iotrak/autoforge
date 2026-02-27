defmodule Autoforge.Deployments.RemoteSSH.KeyCb do
  @moduledoc """
  SSH key callback module for `:ssh` that provides an in-memory private key
  instead of reading from the filesystem.

  Handles OpenSSH-format PEM keys (ed25519) stored on VmInstance records.
  """

  @behaviour :ssh_client_key_api

  @impl true
  def is_host_key(_key, _host, _algorithm, _opts) do
    true
  end

  @impl true
  def user_key(algorithm, opts) do
    pem = opts[:private_key_pem] || Keyword.get(opts[:key_cb_private], :private_key_pem)

    case decode_openssh_key(pem) do
      {:ok, key} ->
        if key_matches_algorithm?(key, algorithm),
          do: {:ok, key},
          else: {:error, :no_matching_key}

      :error ->
        {:error, :no_matching_key}
    end
  end

  @doc """
  Decodes an OpenSSH-format PEM private key into an Erlang key tuple.

  Only supports unencrypted ed25519 keys (the format we generate).
  """
  def decode_openssh_key(pem) when is_binary(pem) do
    with {:ok, blob} <- extract_base64(pem),
         {:ok, key} <- parse_openssh_blob(blob) do
      {:ok, key}
    else
      _ -> :error
    end
  end

  def decode_openssh_key(_), do: :error

  defp extract_base64(pem) do
    b64 =
      pem
      |> String.replace("-----BEGIN OPENSSH PRIVATE KEY-----", "")
      |> String.replace("-----END OPENSSH PRIVATE KEY-----", "")
      |> String.replace(~r/\s+/, "")

    case Base.decode64(b64) do
      {:ok, blob} -> {:ok, blob}
      :error -> :error
    end
  end

  defp parse_openssh_blob(<<"openssh-key-v1", 0, rest::binary>>) do
    with {:ok, _cipher, rest} <- read_string(rest),
         {:ok, _kdf, rest} <- read_string(rest),
         {:ok, _kdf_options, rest} <- read_string(rest),
         <<1::32-big, rest::binary>> <- rest,
         {:ok, _pub_blob, rest} <- read_string(rest),
         {:ok, priv_section, _rest} <- read_string(rest) do
      parse_private_section(priv_section)
    else
      _ -> :error
    end
  end

  defp parse_openssh_blob(_), do: :error

  defp parse_private_section(<<check1::32-big, check2::32-big, rest::binary>>)
       when check1 == check2 do
    with {:ok, "ssh-ed25519", rest} <- read_string(rest),
         {:ok, pub_raw, rest} <- read_string(rest),
         {:ok, priv_combined, _rest} <- read_string(rest) do
      # priv_combined is 64 bytes: 32 bytes private + 32 bytes public
      <<priv_raw::binary-size(32), _pub::binary-size(32)>> = priv_combined
      {:ok, {:ed_pri, :ed25519, pub_raw, priv_raw}}
    else
      _ -> :error
    end
  end

  defp parse_private_section(_), do: :error

  defp read_string(<<len::32-big, data::binary-size(len), rest::binary>>), do: {:ok, data, rest}
  defp read_string(_), do: :error

  defp key_matches_algorithm?({:ed_pri, :ed25519, _, _}, :"ssh-ed25519"), do: true
  defp key_matches_algorithm?(_, _), do: false
end
