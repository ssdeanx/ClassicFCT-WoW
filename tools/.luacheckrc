-- tools/.luacheckrc - lint configuration for the VERIFICATION tools.
--
-- These files are not shipped (tools/ is excluded from the release zip by the
-- explicit manifest in tools/package.sh). They are linted anyway, with their
-- own configuration, because a harness that does not compile is a test suite
-- that silently proves nothing.
--
-- The tools use the io and os standard libraries - the release gate shells
-- out to luacheck and to the behaviour suite, and the behaviour suite exits
-- with a status code. The addon sources must NOT use them (.luarc.json
-- disables them for that reason); the tools are not addon code.

std = "lua51"

-- The harness and the gate both build long, structured lines.
max_line_length = 200

globals = {
    -- The tools read and write files and shell out.
    "io",
    "os",
}
