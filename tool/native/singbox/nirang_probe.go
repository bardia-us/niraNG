package libbox

import "github.com/sagernet/sing-box/daemon"

// StartProbe starts this independently owned service without opening a command
// listener or writing the process-wide active configuration diagnostic snapshot.
// It retains the normal StartedService parser, DNS, routing and outbound engine.
func (s *CommandServer) StartProbe(configContent string) error {
	return s.StartedService.StartOrReloadService(s.ctx, configContent, &daemon.OverrideOptions{})
}
