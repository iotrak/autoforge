defmodule Autoforge.Accounts.SSHKeygen do
  @moduledoc """
  Generates ed25519 SSH keypairs in OpenSSH format.

  Public keys are encoded in OpenSSH wire format (`ssh-ed25519 <base64> autoforge`).
  Private keys are encoded in OpenSSH PEM format (openssh-key-v1, unencrypted).
  """

  @key_type "ssh-ed25519"
  @comment "autoforge"
  @auth_magic "openssh-key-v1\0"
  @cipher_name "none"
  @kdf_name "none"
  @kdf_options ""
  @num_keys 1

  @doc """
  Generates an ed25519 SSH keypair.

  Returns `{public_key_openssh, private_key_pem}` where:
  - `public_key_openssh` is the public key in OpenSSH authorized_keys format
  - `private_key_pem` is the private key in OpenSSH PEM format
  """
  @spec generate() :: {String.t(), String.t()}
  def generate do
    {pub_key, priv_key} = :crypto.generate_key(:eddsa, :ed25519)

    public_key_openssh = encode_public_key(pub_key)
    private_key_pem = encode_private_key(pub_key, priv_key)

    {public_key_openssh, private_key_pem}
  end

  defp encode_public_key(pub_key) do
    blob = ssh_string(@key_type) <> ssh_string(pub_key)
    "#{@key_type} #{Base.encode64(blob)} #{@comment}"
  end

  defp encode_private_key(pub_key, priv_key) do
    # Build the public key blob (same as in authorized_keys, without base64)
    pub_blob = ssh_string(@key_type) <> ssh_string(pub_key)

    # Check number — two identical random uint32s for integrity verification
    check = :crypto.strong_rand_bytes(4)

    # Build the private section (unencrypted)
    # Format: checkint1 || checkint2 || keytype || pubkey || privkey||pubkey || comment || padding
    private_section =
      check <>
        check <>
        ssh_string(@key_type) <>
        ssh_string(pub_key) <>
        ssh_string(priv_key <> pub_key) <>
        ssh_string(@comment)

    # Pad to block size (8 bytes for unencrypted)
    padded = pad_to_block_size(private_section, 8)

    # Assemble the full blob
    blob =
      @auth_magic <>
        ssh_string(@cipher_name) <>
        ssh_string(@kdf_name) <>
        ssh_string(@kdf_options) <>
        <<@num_keys::unsigned-big-integer-size(32)>> <>
        ssh_string(pub_blob) <>
        ssh_string(padded)

    # PEM-encode
    base64 =
      blob
      |> Base.encode64()
      |> chunk_lines(70)

    "-----BEGIN OPENSSH PRIVATE KEY-----\n#{base64}\n-----END OPENSSH PRIVATE KEY-----\n"
  end

  defp ssh_string(data) when is_binary(data) do
    <<byte_size(data)::unsigned-big-integer-size(32), data::binary>>
  end

  defp pad_to_block_size(data, block_size) do
    remainder = rem(byte_size(data), block_size)

    if remainder == 0 do
      data
    else
      pad_len = block_size - remainder
      padding = :binary.list_to_bin(Enum.map(1..pad_len, &rem(&1, 256)))
      data <> padding
    end
  end

  defp chunk_lines(string, width) do
    string
    |> String.graphemes()
    |> Enum.chunk_every(width)
    |> Enum.map_join("\n", &Enum.join/1)
  end
end
