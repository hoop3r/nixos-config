# neo4j-shell.nix
{
  pkgs ? import <nixpkgs> { },
}:

pkgs.mkShell {
  name = "neo4j-shell";

  packages = [ pkgs.neo4j ];

  shellHook = ''
        export NEO4J_CONF="$HOME/.config/neo4j"

        mkdir -p "$HOME/.neo4j/data"
        mkdir -p "$HOME/.neo4j/logs"
        mkdir -p "$HOME/.neo4j/run"
        mkdir -p "$HOME/.neo4j/plugins"
        mkdir -p "$HOME/.neo4j/import"
        mkdir -p "$NEO4J_CONF"

        cat > "$NEO4J_CONF/neo4j.conf" << EOF
    server.http.enabled=true
    server.http.listen_address=localhost:7474
    server.http.advertised_address=localhost:7474
    server.bolt.enabled=true
    server.bolt.listen_address=localhost:7687
    server.bolt.advertised_address=localhost:7687
    server.https.enabled=false

    server.directories.data=$HOME/.neo4j/data
    server.directories.logs=$HOME/.neo4j/logs
    server.directories.run=$HOME/.neo4j/run
    server.directories.plugins=$HOME/.neo4j/plugins
    server.directories.import=$HOME/.neo4j/import

    server.logs.user.config=$HOME/.config/neo4j/user-logs.xml
    server.logs.config=$HOME/.config/neo4j/server-logs.xml
    EOF

        cat > "$NEO4J_CONF/user-logs.xml" << 'EOF'
    <?xml version="1.0" encoding="UTF-8"?>
    <Configuration status="ERROR" monitorInterval="30">
      <Appenders>
        <RollingRandomAccessFile name="Neo4jLog" fileName="${"sys:NEO4J_HOME"}/logs/neo4j.log"
            filePattern="${"sys:NEO4J_HOME"}/logs/neo4j.log.%02i">
          <PatternLayout pattern="%d{yyyy-MM-dd HH:mm:ss.SSSZ}{UTC} %-5p %m%n"/>
          <Policies>
            <SizeBasedTriggeringPolicy size="20 MB"/>
          </Policies>
          <DefaultRolloverStrategy fileIndex="min" max="7"/>
        </RollingRandomAccessFile>
      </Appenders>
      <Loggers>
        <Root level="INFO">
          <AppenderRef ref="Neo4jLog"/>
        </Root>
      </Loggers>
    </Configuration>
    EOF

        cat > "$NEO4J_CONF/server-logs.xml" << 'EOF'
    <?xml version="1.0" encoding="UTF-8"?>
    <Configuration status="ERROR" monitorInterval="30">
      <Appenders>
        <RollingRandomAccessFile name="DebugLog" fileName="${"sys:NEO4J_HOME"}/logs/debug.log"
            filePattern="${"sys:NEO4J_HOME"}/logs/debug.log.%02i">
          <PatternLayout pattern="%d{yyyy-MM-dd HH:mm:ss.SSSZ}{UTC} %-5p [%c{1.}] %m%n"/>
          <Policies><SizeBasedTriggeringPolicy size="20 MB"/></Policies>
          <DefaultRolloverStrategy fileIndex="min" max="7"/>
        </RollingRandomAccessFile>
        <RollingRandomAccessFile name="HttpLog" fileName="${"sys:NEO4J_HOME"}/logs/http.log"
            filePattern="${"sys:NEO4J_HOME"}/logs/http.log.%02i">
          <PatternLayout pattern="%d{yyyy-MM-dd HH:mm:ss.SSSZ}{UTC} %-5p %m%n"/>
          <Policies><SizeBasedTriggeringPolicy size="20 MB"/></Policies>
          <DefaultRolloverStrategy fileIndex="min" max="7"/>
        </RollingRandomAccessFile>
        <RollingRandomAccessFile name="QueryLog" fileName="${"sys:NEO4J_HOME"}/logs/query.log"
            filePattern="${"sys:NEO4J_HOME"}/logs/query.log.%02i">
          <PatternLayout pattern="%d{yyyy-MM-dd HH:mm:ss.SSSZ}{UTC} %-5p %m%n"/>
          <Policies><SizeBasedTriggeringPolicy size="20 MB"/></Policies>
          <DefaultRolloverStrategy fileIndex="min" max="7"/>
        </RollingRandomAccessFile>
        <RollingRandomAccessFile name="SecurityLog" fileName="${"sys:NEO4J_HOME"}/logs/security.log"
            filePattern="${"sys:NEO4J_HOME"}/logs/security.log.%02i">
          <PatternLayout pattern="%d{yyyy-MM-dd HH:mm:ss.SSSZ}{UTC} %-5p %m%n"/>
          <Policies><SizeBasedTriggeringPolicy size="20 MB"/></Policies>
          <DefaultRolloverStrategy fileIndex="min" max="7"/>
        </RollingRandomAccessFile>
      </Appenders>
      <Loggers>
        <Root level="INFO">
          <AppenderRef ref="DebugLog"/>
        </Root>
        <Logger name="HttpLogger" level="INFO" additivity="false">
          <AppenderRef ref="HttpLog"/>
        </Logger>
        <Logger name="QueryLogger" level="INFO" additivity="false">
          <AppenderRef ref="QueryLog"/>
        </Logger>
        <Logger name="SecurityLogger" level="INFO" additivity="false">
          <AppenderRef ref="SecurityLog"/>
        </Logger>
      </Loggers>
    </Configuration>
    EOF

        echo ""
        echo "Neo4j dev shell ready"
        echo "  Config : $NEO4J_CONF"
        echo "  Data   : $HOME/.neo4j/data"
        echo "  Logs   : $HOME/.neo4j/logs"
        echo ""
  '';
}
