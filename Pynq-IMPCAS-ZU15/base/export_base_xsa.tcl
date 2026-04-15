set script_path [file normalize [info script]]
set script_dir  [file dirname $script_path]

set xsa_name "base"
set output_file "${script_dir}/${xsa_name}.xsa"

if {[current_project -quiet] == ""} {
    puts "Error: No project open. Please open a project before running this script."
} else {
    puts "Exporting XSA to: $output_file"
    catch {
        write_hw_platform -fixed -include_bit -force -file $output_file
    } result
    puts "Result: $result"
}
