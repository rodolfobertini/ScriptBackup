# backup_rotativo.ps1

## Descrição

Script PowerShell para backup rotativo de arquivos, com configuração interativa, validação, auto-instalação e agendamento automático via Agendador de Tarefas do Windows.

## Requisitos

- Windows com interface gráfica (usa Windows Forms e MessageBox)
- PowerShell rodando como Administrador
- Permissões de leitura na pasta monitorada e escrita na pasta de destino
- Permissão para criar tarefas agendadas (necessário rodar como Administrador)

## Instalação e Uso

1. **Execute o script como Administrador**  
   Clique com o botão direito no `backup_rotativo.ps1` e escolha "Executar com PowerShell (Administrador)".

2. **Configuração Interativa**  
   Na primeira execução, o script solicitará:
   - Pasta a ser monitorada (origem dos arquivos de backup)
   - Pasta de destino dos backups rotativos
   - Quantidade de backups a manter (retenção)
   - Intervalo de execução em minutos

3. **Agendamento Automático**  
   O script se auto-instala em `C:\RodolfoScriptBackup\` e agenda a execução automática conforme o intervalo definido.

4. **Funcionamento**  
   - A cada execução, copia o arquivo mais recente da pasta monitorada para a pasta de destino, com nome baseado na data/hora.
   - Mantém apenas o número de backups definido, removendo os mais antigos automaticamente.

## Permissões Necessárias

- **Administrador:** Necessário para criar tarefas agendadas e acessar pastas protegidas.
- **Acesso às Pastas:** O usuário (ou conta SYSTEM, usada no agendamento) precisa de permissão de leitura na pasta monitorada e escrita na pasta de destino.

## Observações

- O script salva a configuração em `C:\RodolfoScriptBackup\config_backup.json`.
- Para alterar a configuração, exclua esse arquivo e execute o script novamente.
- O script exibe notificações gráficas ao concluir ou em caso de erro.

## Limitações

- Funciona apenas em Windows com interface gráfica.
- Não faz backup de subpastas, apenas arquivos diretamente na pasta monitorada.

---