# backup_rotativo.ps1

## Descrição

Script PowerShell para backup rotativo de arquivos, com configuração interativa, validação, auto-instalação e agendamento automático via Agendador de Tarefas do Windows.

## Requisitos

- Windows com interface gráfica (usa Windows Forms e MessageBox)
- PowerShell 5.1 ou superior
- Permissões de leitura na pasta monitorada e escrita na pasta de destino
- Permissão para criar tarefas agendadas (necessário rodar como Administrador)

## Instalação e Uso

1. **Execute o script normalmente**  
   Se não estiver em modo Administrador, o próprio script solicitará elevação automática (UAC) e será reiniciado com privilégios elevados.

2. **Configuração Interativa**  
   Na primeira execução, o script solicitará:
   - Pasta a ser monitorada (origem dos arquivos de backup)
   - Pasta de destino dos backups rotativos
   - Quantidade de backups a manter (retenção)
   - Intervalo de execução em minutos

3. **Agendamento Automático**  
   O script se auto-instala em `C:\RodolfoScriptBackup\` e agenda a execução automática conforme o intervalo definido, usando a conta SYSTEM e privilégios elevados.

4. **Funcionamento**  
   - A cada execução, copia o arquivo mais recente da pasta monitorada para a pasta de destino, mantendo o mesmo nome do arquivo original.
   - Mantém apenas o número de backups definido, removendo os mais antigos automaticamente.
   - Não faz backup se não houver alteração no arquivo mais recente desde a última execução.
   - Todas as ações e erros são registrados em `backup_log.txt`.

## Permissões Necessárias

- **Administrador:** Necessário para criar tarefas agendadas e acessar pastas protegidas.
- **Acesso às Pastas:** A conta SYSTEM (usada no agendamento) precisa de permissão de leitura na pasta monitorada e escrita na pasta de destino.

## Observações

- O script salva a configuração em `C:\RodolfoScriptBackup\config_backup.json`.
- Para alterar a configuração, exclua esse arquivo e execute o script novamente.
- O script exibe notificações gráficas ao concluir ou em caso de erro.
- O script encerra automaticamente após a execução.

## Limitações

- Funciona apenas em Windows com interface gráfica.
- Não faz backup de subpastas, apenas arquivos diretamente na pasta monitorada.
- A conta SYSTEM pode não ter acesso a pastas de usuário (ex: `C:\Users\SeuUsuario\Documents`). Ajuste as permissões se necessário.

---