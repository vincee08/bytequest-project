import { randomInt } from 'node:crypto';

export interface PracticeQuestion {
  id: string;
  question: string;
  choices: string[];
  answer: number;
  explanation: string;
  page: number;
}

// Grounded in Computer-Systems-Servicing-NC-II_copy.pdf, SAG ELCCSS 213-0119.
// The 80% learning threshold is ByteQuest policy, not TESDA certification.
const q = (id: string, page: number, question: string, choices: string[], explanation: string): PracticeQuestion =>
  ({ id, page, question, choices, answer: 0, explanation });
export const practiceBank: Record<string, PracticeQuestion[]> = {
  coc1: [
    q('c1-safety',1,'What should you do before fitting a motherboard?', ['Isolate power and prepare ESD protection','Keep the supply energized','Hold the board by its contacts','Place the board directly on carpet'], 'Isolation prevents electrical hazards; ESD controls protect sensitive parts.'),
    q('c1-keying',1,'A memory module does not fit the socket. What should you inspect?', ['Module compatibility and notch alignment','Whether extra force will seat it','The desktop wallpaper','The printer queue'], 'Socket type and keying must match; force can damage the socket or module.'),
    q('c1-firmware',1,'Your installation USB and GPT disk require UEFI. Which boot setting fits?', ['UEFI boot mode','Disable the storage controller','Boot from an unrelated network adapter','Ignore firmware settings'], 'UEFI boot mode matches the installation media and GPT system-disk work order.'),
    q('c1-media',1,'How should bootable installation media be prepared?', ['Follow the vendor instructions and verify the media','Copy any shortcut onto the USB','Use an unverified download','Delete the license documentation'], 'The guide requires portable bootable devices prepared according to software manufacturer instructions.'),
    q('c1-license',1,'Before installing an application and portable utility, what must be checked?', ['Installation guide and applicable licenses','Only the icon color','Whether a license can be bypassed','Only the download count'], 'Application and portable software must follow user guides and applicable license agreements.'),
    q('c1-updates',1,'Which source should guide OS and driver updates?', ['Verified manufacturer recommendations','An unidentified executable','A disabled update service forever','A random social-media attachment'], 'Verify update provenance and compatibility against manufacturer requirements.'),
    q('c1-test',1,'The PC boots after assembly. What verifies reliability beyond that single boot?', ['Functional verification and a monitored stress test','Assume all components are reliable','Remove the cooling fan','Skip the final inspection'], 'The guide calls for both conformance testing and stress testing to check equipment reliability.'),
    q('c1-report',2,'How should completed installation work be closed out?', ['Follow 5S and 3Rs and forward technical documentation','Leave debris and omit the report','Discard the test observations','Mark the work complete without checking it'], 'The COC1 guide includes environmental close-out and documentation for appropriate personnel.'),
  ],
  coc2: [
    q('c2-route',3,'What should guide the cable route before installation?', ['The network design and safe installation requirements','The shortest route regardless of hazards','A route across an unprotected walkway','An unrelated device diagram'], 'Cable routes and raceway installation must follow the network design and installation requirements.'),
    q('c2-wiremap',3,'How do you verify a requested T568B termination?', ['Check conductor order and the tester wire map','Check only the cable jacket color','Assume the plug shape proves continuity','Skip inspection after crimping'], 'The guide names 568A/568B coding and checking the completed installation; a wire map detects opens and order faults.'),
    q('c2-topology',3,'In a switched star, where should each workstation connect?', ['To the switch using a compatible Ethernet link','Directly to every other workstation','To the power-conditioning outlet as a data link','To an HDMI port'], 'Ethernet interfaces and the requested topology determine valid network links.'),
    q('c2-address',3,'A client is assigned 192.168.10.24/24. Which mask represents /24?', ['255.255.255.0','255.0.0.0','0.0.0.0','255.255.255.255'], 'A /24 mask has 24 network bits: 255.255.255.0. Addressing must match the network design.'),
    q('c2-wifi',4,'The work order requires WPA2/AES Wi-Fi. Which configuration complies?', ['The specified SSID with WPA2/AES','An open network','Disable encryption for convenience','Change the SSID without documenting it'], 'Wireless configuration and client access must match the network design and stated security policy.'),
    q('c2-firewall',4,'Which policy meets a requirement to block unsolicited inbound traffic?', ['Deny unsolicited inbound connections','Allow all inbound traffic','Disable all firewall checks','Open every service port'], 'Firewall rules should meet the stated security requirement while permitting authorized services.'),
    q('c2-wan',4,'The upstream router supplies WAN addresses dynamically. Which uplink mode fits?', ['DHCP on the WAN interface','Disable the WAN port','Assign the switch port an HDMI signal','Use an unrelated fixed address'], 'A DHCP WAN uplink follows the specified upstream addressing design; verify the lease and connectivity.'),
    q('c2-diagnosis',3,'A terminal cannot reach a shared resource. What is a sound diagnostic approach?', ['Inspect links, test addressing, localize the fault, and retest after correction','Replace every device immediately','Change settings randomly','Declare success from a link light alone'], 'The guide requires terminal communication checks, fault diagnosis, remedies, and response to unplanned conditions.'),
  ],
  coc3: [
    q('c3-role',5,'The Support team needs shared files. Which service should be prepared?', ['A file service with the requested access policy','Only a display driver','An unrelated game service','A service with no user permissions'], 'Confirm network services against user and system requirements before configuration.'),
    q('c3-folder',5,'What should accompany creation of a technician user folder?', ['Access permissions matching network policy','Unrestricted access for all accounts','A public administrative password','No security check'], 'User folders and access levels must follow NOS features, network policy, and end-user requirements.'),
    q('c3-permission',5,'Support requires Modify; Learners require Read. Which assignment fits?', ['Support: Modify; Learners: Read','Everyone: Modify','Learners: administrator','Support: no access'], 'Assign the requested access levels and test both authorized and restricted user access.'),
    q('c3-modules',5,'How should required NOS modules be installed or updated?', ['Follow NOS installation procedures and verify normal function','Load unverified modules','Ignore version compatibility','Disable all service tests'], 'The guide requires modules/add-ons following NOS procedures and normal server-function checks.'),
    q('c3-service',5,'Your file-service work order specifies TCP 445. What should a client test verify?', ['The configured listener and authorized file access','Only the server wallpaper','Only that the server fan spins','Any unrelated open port'], 'A listening port alone is insufficient; test the requested network service from the client.'),
    q('c3-printer',5,'Which task belongs in server pre-deployment testing?', ['Client file and printer sharing with documented results','Only naming the server','Only replacing the monitor','Skipping security checks'], 'The guide explicitly names file and printer sharing, documentation, and pre-deployment procedures.'),
    q('c3-recovery',5,'A technician loses access because Support membership is missing. What is appropriate?', ['Restore authorized membership and verify access','Grant Modify to Everyone','Disable all access controls','Reinstall the client without diagnosis'], 'Correct the measured permission fault while preserving established access policy.'),
    q('c3-handover',5,'Before deploying a configured server, what must be completed?', ['Operation and security checks plus the enterprise report','Only a restart','Only an installation screenshot','A report with no test evidence'], 'COC3 includes pre-deployment procedures, operation/security checks, and enterprise reporting.'),
  ],
  coc4: [
    q('c4-plan',6,'What should guide maintenance and diagnosis first?', ['The job/service order and checked tools','An untested guess','Replacing all hardware','Ignoring the reported symptom'], 'Plan maintenance and diagnosis against job requirements and verify tool operation and safety.'),
    q('c4-storage',6,'Storage reports pending sectors while memory tests show no errors. What is justified?', ['Protect data and investigate the storage fault','Replace memory based only on the symptom','Erase the drive before backup','Ignore the storage measurement'], 'Use measured diagnostics to localize a fault and protect data through contingency measures.'),
    q('c4-repair',6,'What is essential before replacing a faulty adapter?', ['Power isolation, ESD protection, and compatibility checks','Live removal without precautions','Forcing incompatible keying','Touching exposed contacts unnecessarily'], 'Follow OHS and replace components without damage to surrounding equipment or services.'),
    q('c4-contingency',6,'Which step protects continuity during a repair?', ['Verify backup and plan recovery or escalation','Discard service records','Disable backup permanently','Change every setting at once'], 'The guide requires managing and implementing contingency measures according to established procedures.'),
    q('c4-maintenance',6,'When should scheduled maintenance be performed?', ['According to manufacturer requirements and the service schedule','Only after every device fails','On an arbitrary schedule without inspection','Without the required protective equipment'], 'Periodic maintenance and normal-function checks must follow manufacturer requirements.'),
    q('c4-retest',7,'After correcting a fault, what proves the repair?', ['Fresh functional testing and final safe-operation inspection','Reusing a test performed before the change','Only closing the case','Only recording that a part was purchased'], 'Fresh testing verifies the changed system and the guide requires final inspection and safe operation.'),
    q('c4-environment',7,'Which environmental close-out is named in the COC4 guide?', ['Clear debris and follow 5S and 4Rs','Leave replaced parts across the workspace','Mix hazardous debris with useful parts','Skip work-site cleanup'], 'The supplied COC4 guide specifically names clearing debris, 5S, and 4Rs.'),
    q('c4-report',7,'What should a repair report contain?', ['Observed fault, corrective work, fresh test results, and handover details','Only a claimed success','Only the learner name','No diagnostic evidence'], 'Reporting should document the service work and final verification against company requirements.'),
  ],
};

export function selectPracticeQuestions(coc: string): PracticeQuestion[] {
  const bank = practiceBank[coc];
  if (!bank) throw new Error('INVALID_COC');
  const pool = bank.map(q => ({ ...q, choices: [...q.choices] }));
  for (let i=pool.length-1;i>0;i--) { const j=randomInt(i+1); [pool[i],pool[j]]=[pool[j],pool[i]]; }
  return pool.slice(0,5).map(item => {
    const options = item.choices.map((text,index)=>({text,index}));
    for (let i=options.length-1;i>0;i--) { const j=randomInt(i+1); [options[i],options[j]]=[options[j],options[i]]; }
    return {...item,choices:options.map(o=>o.text),answer:options.findIndex(o=>o.index===item.answer)};
  });
}
