defmodule Kenwood.TS570D do

  @moduledoc """
  Attributes and custom fucntions for the Kenwood TS-570 series transceivers
  """

  def attributes, do: %{
    ant_tuner:    {"AC",  3, [000,100,110,111]},
#   af_gain:      {"AG",  3, 0..255, p1: "0"},
    rf_gain:      {"RG",  3, 0..255},
    beat_cancel:  {"BC",  1, :bool},
    notch_freq:   {"BP",  3, 0..127},
    cw_autotune:  {"CA",  1, :bool},
    carrier:      {"CG",  3, 0..100},
    ctcss_freq:   {"CN",  2, 0..41},
    ctcss_mode:   {"CT",  1, 0..2},
    data_mode:    {"DA",  1, :bool},
    freq_a:       {"FA",  11, 30000..30000000},
    freq_b:       {"FB",  11, 30000..30000000},
    if_filter:    {"FL",  1, 1..2},
    func_rx:      {"FR",  1, 0..2},
    func_tx:      {"FT",  1, 0..2},
    fine_tune:    {"FS",  1, :bool},
    fw_version:   {"FV",  4, :ro_string},
    filter_width: {"FW",  4, 0..9999 },
    agc_mode:     {"GC",  1, 0..2},
    agc_speed:    {"GT",  2, 1..20},
    model:        {"ID",  3, :ro_bool},
#    if_shift:     {"IS",  4, 0..9999, p1: " ", query: "IS" }}
    cw_speed:     {"KS",  3, 4..60 },
    mode:         {"MD",  1, 0..9 },
    mic_gain:     {"MG",  3, 0..100 },
    monitor_lvl:  {"ML",  3, 0..9 },
    nb_mode:      {"NB",  1, 0..2 },
    nb_level:     {"NL",  3, 1..10},
    nr_mode:      {"NR",  1, 0..2},
    notch_mode:   {"NT",  2, [00,10,20,21]},
#    preamp:       {"PA",  &} # weird!!!!
    rf_power:     {"PC",  3, 5..100},  # should use validator for am 25w limit
#   proc_in, proc_out -> "PL", complicated
    speech_proc:  {"PR",  1, :bool},
#    power_switch: {"PS",  1, :bool},     # handled elsewhere
    rf_gain:      {"RG",  3, 0..255},
    nr_level:     {"RL",  2, 01.10},
    rit:          {"RT",  1, :bool},
    #  ru/rd -- complicated
    #  ra: rf attenuator - complicate dmapping function
    #  sc - too comlicated
    cw_breakin:   {"SD", 4, 0..1000 },
    high_cut:     {"SH", 2, 0..99},
    low_cut:      {"SL", 2, 0..99},
    tone_freq:    {"TN", 2, 0..42},
    tone_encode:  {"TO", 1, :bool},
    tf_set:       {"TS", 1, :bool},
    vox_delay:    {"VD", 4, 0..3000},
    vox_gain:     {"VG", 3, 0..9},
    vox:          {"VX", 1, :bool},
    xit:          {"XT", 1, :bool}
    # antenna_nubmer:  {:simple,   {"AN",  3, 0..255} },
    # s_meter:      {"SM", 4, 0..30, read_only: true, p1:"0"}
    # fv - firmware version
  }

end
