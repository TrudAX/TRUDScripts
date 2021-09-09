# The script rebuilds files in the (Src, Test, Examples) directories based on *.xpo project files

#Requires -Version 5
#Requires -module @{ ModuleName="xpoTools"; ModuleVersion="1.2.0" }

Get-ChildItem ax2009, ax2012, ax4 -filter '*.xpo' -ErrorAction SilentlyContinue | ForEach-Object {
    $Path = $_.DirectoryName
    Import-Xpo $_ | Split-xpo -Destination $Path -Exclude SharedProject_* -xpp -PathStyle mazzy -PassThru
}
