{ lib, config, mainUser, mylib, ... }:
let
  hostCfg = config.my.host;
  roleFlags = mylib.roleFlags hostCfg;
  inherit (roleFlags) enableDocker useRootlessDocker useRootfulDocker;
in
{
  # Docker 容器（rootful/rootless 可切换）
  virtualisation.docker = {
    enable = enableDocker && useRootfulDocker;
    enableOnBoot = false; # 按需 socket activation 启动（减少开机时间）
    autoPrune = {
      enable = true;
      dates = "weekly";
      flags = [ "--all" ]; # 清理所有未使用的镜像（不仅悬空镜像）
    };
  };
  virtualisation.docker.rootless = {
    enable = enableDocker && useRootlessDocker;
    setSocketVariable = true;
  };

  # Docker rootless containerd 需要 /opt/containerd 可写（tmpfs root 下不存在）
  systemd.tmpfiles.rules = lib.mkIf (enableDocker && useRootlessDocker) [
    "d /opt 0755 root root -"
    "d /opt/containerd 0755 ${mainUser} ${mainUser} -"
  ];

  # greetd 的 greeter 用户也会拉起一个 user manager；
  # 将仅主用户需要的 user services 绑定到 mainUser，避免 greeter 会话产生误报失败日志。
  systemd.user = lib.mkIf (enableDocker && useRootlessDocker) {
    services.docker.unitConfig.ConditionUser = lib.mkForce mainUser;
  };

  users.groups.docker = lib.mkIf (enableDocker && useRootlessDocker) { };

  users.users.${mainUser} = {
    linger = lib.mkIf (enableDocker && useRootlessDocker) (lib.mkDefault true);
    extraGroups = lib.mkAfter (lib.optionals (enableDocker && useRootfulDocker) [ "docker" ]);
  };
}
