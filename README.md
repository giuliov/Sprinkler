## Project Description

Sprinkler is a set of Powershell v2 scripts that helps in deploying multiple packages on as server farm. A configuration file drives its behavior, so it can be used on different environments (DEV, TEST, PROD, ...). Used in conjunction with BTDF, it is ready for BizTalk . Notable features are:

- Parallelization of execution — the tool must be run on all servers of the farm and will operate concurrently as much as possible, reducing deployment time window;
- Can be run from a central location by leveraging Powershell v2 remoting;
- Script based — requires Powershell v2, no additional component to install on any server; you can Zip everything and send it to a different site;
- Flexible layout — keep all the files in a single share or spread them in different locations to keep sensitive information in a safe place or in a read-only folder;
- Simple configuration — all parameters for execution are contained in just two files;
- Interactive and unattended mode — an menu driven wizard helps choosing the script to run and its parameters;
- Complete and centralized logging in plain text files;
- Can execute sections of code in 32-bits for compatibility;
- Rich library for operating BizTalk — stopping host instances, setting host adapters, starting and stopping applications in order, BRE rules managing;
- Add new scripts and functions that leverage all above features.
