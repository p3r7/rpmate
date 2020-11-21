--
-- devices
--


-- -------------------------------------------------------------------------
-- CONSTANTS

-- record / playback speeds
rpm_hz_list    =  { 0.28, 0.55, 0.75, 1.3, 2.667, 8.667 }
rpm_label_list =  { "16", "33", "45", "78", "160", "520" }

-- devices: input
rpm_device_list = { "tt-16", "tt-33", "tt-45", "tt-78", "edison-cylinder", "washing-machine" }
rpm_device_w =    { 26, 26, 26, 26, 27, 100 }
rpm_device_y =             { 20, 20, 20, 20, 10, 10 }
rpm_device_cnnx_rel_x =    { 17, 17, 17, 17, 17, 0 }
rpm_device_cnnx_rel_y =    { 0, 0, 0, 0, 20, 0 }

-- device: norns
norns_w = 14
norns_in_rel_x = 6
norns_out_rel_x = 9
norns_x = nil
norns_in_x = nil
norns_out_x = nil

-- devices: hw samplers
sampler_label_list =  { "MPC 2k", "S950", "SP-404" }
sampler_device_list = { "mpc-2k_2", "s950", "sp-404" }
sampler_device_w =    { 28, 33, 13 }
sampler_device_cnnx_rel_x =    { 17, 22, 5 }
