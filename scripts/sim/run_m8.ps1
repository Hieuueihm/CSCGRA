param(
    [switch]$EnableProperties,
    [string]$VivadoBin = "C:\Xilinx\Vivado\2018.1\bin"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$workName = if ($EnableProperties) { "m8_property_xsim" } else { "m8_xsim" }
$workRoot = Join-Path $repoRoot "work\$workName"
New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
$xvlog = Join-Path $VivadoBin "xvlog.bat"
$xelab = Join-Path $VivadoBin "xelab.bat"
$xsim = Join-Path $VivadoBin "xsim.bat"

& py -3 (Join-Path $repoRoot "scripts\golden\generate_m10_full_refinement_vectors.py")
if ($LASTEXITCODE -ne 0) { throw "M10 full refinement golden generation failed" }

$sources = @(
    "rtl\v3\memory\recon_sdp_ram.v",
    "rtl\v3\memory\recon_1w2r_ram.v",
    "rtl\v3\memory\support_coefficient_stripe_store.v",
    "rtl\v3\context_control\context_reservation_guard.v",
    "rtl\v3\context_control\array_context_sequencer.v",
    "rtl\v3\reconstruction_control\resident_execution_state.v",
    "rtl\v3\data_movement\vector_scratchpad.v",
    "rtl\v3\data_movement\scratchpad_subsystem.v",
    "rtl\v3\data_movement\vector_stream_engine.v",
    "rtl\v3\data_movement\scratchpad_word_codec.v",
    "rtl\v3\data_movement\vector_codec_write_subsystem.v",
    "rtl\v3\data_movement\vector_ingress_adapter.v",
    "rtl\v3\data_movement\normalized_result_writeback.v",
    "rtl\v3\cgra\stream_context_router.v",
    "rtl\v3\cgra\pe_alu.v",
    "rtl\v3\cgra\phi_pe_alu.v",
    "rtl\v3\cgra\pe_local_register_file.v",
    "rtl\v3\cgra\registered_switchbox.v",
    "rtl\v3\cgra\pe_tile.v",
    "rtl\v3\cgra\phi_pe_tile.v",
    "rtl\v3\cgra\cgra_row.v",
    "rtl\v3\cgra\cgra_cluster.v",
    "rtl\v3\cgra\cgra_cluster_pair.v",
    "rtl\v3\cgra\cgra_result_buffer.v",
    "rtl\v3\cgra\cgra_result_capture_adapter.v",
    "rtl\v3\cgra\cgra_execution_fabric.v",
    "rtl\v3\phi\phi_request_queue.v",
    "rtl\v3\phi\threefry2x32_folded_pipeline.v",
    "rtl\v3\phi\phi_symbol_builder.v",
    "rtl\v3\phi\phi_response_gearbox.v",
    "rtl\v3\phi\phi_symbol_generator.v",
    "rtl\v3\phi\support_phi_symbol_cache.v",
    "rtl\v3\phi\phi_stream_provider.v",
    "rtl\v3\phi\phi_stream_subsystem.v",
    "rtl\v3\phi\phi_operator_normalizer.v",
    "rtl\v3\phi\phi_lane_normalization_flow.v",
    "rtl\v3\phi\phi_column_flow.v",
    "rtl\v3\arithmetic\cluster_reduction_unit.v",
    "rtl\v3\arithmetic\global_reduction_merge.v",
    "rtl\v3\arithmetic\reduction_pipeline.v",
    "rtl\v3\arithmetic\scalar_register_file.v",
    "rtl\v3\arithmetic\scalar_state_subsystem.v",
    "rtl\v3\arithmetic\scalar_function_unit.v",
    "rtl\v3\arithmetic\shared_vector_arithmetic_unit.v",
    "rtl\v3\arithmetic\shared_vector_pipeline.v",
    "rtl\v3\arithmetic\array_resource_router.v",
    "rtl\v3\arithmetic\m5_arithmetic_subsystem.v",
    "rtl\v3\selection\topk_selection_unit.v",
    "rtl\v3\selection\proxy_candidate_collector.v",
    "rtl\v3\selection\vector_candidate_serializer.v",
    "rtl\v3\selection\candidate_stream_adapter.v",
    "rtl\v3\selection\support_vector_rebuilder.v",
    "rtl\v3\selection\support_refinement_adapter.v",
    "rtl\v3\selection\support_workspace.v",
    "rtl\v3\selection\support_state_manager.v",
    "rtl\v3\selection\support_coefficient_remapper.v",
    "rtl\v3\refinement\certificate_limit_unit.v",
    "rtl\v3\refinement\normal_residual_checker.v",
    "rtl\v3\refinement\restricted_refinement_state.v",
    "rtl\v3\debug\operator_fault_monitor.v",
    "rtl\v3\debug\operator_fault_event_encoder.v",
    "rtl\v3\integration\m10_refinement_integration.v",
    "rtl\v3\integration\m8_resource_dispatcher.v",
    "rtl\v3\integration\operator_flow_control.v",
    "rtl\v3\integration\m8_operator_harness.v",
    "verification\v3\m8\tb_m8_operator_harness.sv",
    "verification\v3\m8\tb_m8_nested_operators.sv",
    "verification\v3\m8\tb_m8_nested_sequencer.sv"
) | ForEach-Object { Join-Path $repoRoot $_ }
$defines = if ($EnableProperties) { @("-d", "FORMAL") } else { @() }
$includeRoot = Join-Path $repoRoot "rtl\v3\include"
$m10Golden = Join-Path $repoRoot "verification\v3\m10\generated"
$contextImage = Join-Path $repoRoot "reports\v3\context_images"
0..9 | ForEach-Object {
    Copy-Item -Force -LiteralPath (Join-Path $contextImage "array_plane_$_.mem") `
        -Destination $workRoot
}
$allOutput = @()
$tops = @("tb_m8_operator_harness", "tb_m8_nested_operators", "tb_m8_nested_sequencer")

Push-Location $workRoot
try {
    foreach ($source in $sources) {
        & $xvlog -sv @defines -i $includeRoot -i $m10Golden $source
        if ($LASTEXITCODE -ne 0) { throw "M8 compile failed: $source" }
    }
    foreach ($top in $tops) {
        $suffix = if ($EnableProperties) { "property" } else { "normal" }
        $snapshot = "${top}_${suffix}"
        & $xelab $top -s $snapshot -debug typical
        if ($LASTEXITCODE -ne 0) { throw "M8 elaboration failed: $top" }
        $simOutput = & $xsim $snapshot -runall 2>&1
        $code = $LASTEXITCODE
        $simOutput | ForEach-Object { Write-Host $_ }
        $allOutput += $simOutput
        if ($code -ne 0) { throw "M8 simulation failed: $top" }
    }
} finally {
    Pop-Location
}

$report = Join-Path $repoRoot "reports\v3\m8_vivado"
New-Item -ItemType Directory -Force -Path $report | Out-Null
$name = if ($EnableProperties) { "m8_xsim_properties.log" } else { "m8_xsim.log" }
Set-Content -LiteralPath (Join-Path $report $name) -Value $allOutput
$joined = $allOutput -join "`n"
if ($joined -match "FAIL:|Assertion violation") { throw "M8 failure marker" }
if ($joined -notmatch "M8 OPERATOR HARNESS PASS") { throw "M8 correlation PASS marker missing" }
if ($joined -notmatch "M8 NESTED OPERATORS PASS") { throw "M8 nested PASS marker missing" }
if ($joined -notmatch "M8 NESTED SEQUENCER PASS") { throw "M8 sequencer PASS marker missing" }
if ($joined -notmatch "M10 FULL REFINEMENT TRANSACTION PASS") {
    throw "M10 full refinement PASS marker missing"
}
Write-Host "VIVADO M8 XSIM PASS"
