//! User-facing strings from Rust (tray menu, errors, sign-in pages). English is the key; Brazilian
//! Portuguese is used when the system language is Portuguese. The webview has its own table in
//! `frontend/i18n.ts` and follows the same `locale()`.

use std::collections::HashMap;
use std::sync::LazyLock;

static PORTUGUESE: LazyLock<bool> =
    LazyLock::new(|| sys_locale::get_locale().is_some_and(|locale| locale.to_lowercase().starts_with("pt")));

static PT_BR: LazyLock<HashMap<&'static str, &'static str>> = LazyLock::new(|| TRANSLATIONS.iter().copied().collect());

pub fn locale() -> &'static str {
    if *PORTUGUESE {
        "pt-BR"
    } else {
        "en"
    }
}

/// Translates an English string. Placeholders such as `{status}` are replaced by the caller.
pub fn t(english: &str) -> String {
    if *PORTUGUESE {
        if let Some(translation) = PT_BR.get(english) {
            return (*translation).to_owned();
        }
    }
    english.to_owned()
}

const TRANSLATIONS: &[(&str, &str)] = &[
    ("Add an API key in Settings.", "Adicione uma chave de API nas Configurações."),
    ("ChatGPT connection failed", "A conexão com o ChatGPT falhou"),
    ("ChatGPT login timed out.", "O login do ChatGPT expirou."),
    ("ChatGPT session refresh failed ({status}).", "A renovação da sessão do ChatGPT falhou ({status})."),
    ("ChatGPT token exchange failed ({status}).", "A troca de token do ChatGPT falhou ({status})."),
    ("Check for Updates…", "Procurar Atualizações…"),
    ("Check the email address, or leave it empty.", "Confira o endereço de e-mail ou deixe o campo vazio."),
    ("Couldn't send your feedback. Check your connection and try again.", "Não foi possível enviar seu feedback. Confira sua conexão e tente de novo."),
    ("Closing in {seconds}…", "Fechando em {seconds}…"),
    ("Connected to ChatGPT", "Conectado ao ChatGPT"),
    ("Copied. Paste it with Ctrl+V.", "Copiado. Cole com Ctrl+V."),
    ("Copied. This session can't insert text automatically, so paste it with Ctrl+V.", "Copiado. Esta sessão não consegue inserir texto automaticamente, então cole com Ctrl+V."),
    ("Copied to clipboard.", "Copiado para a área de transferência."),
    ("Couldn't reach Feather Plus. Check your connection.", "Não foi possível acessar o Feather Plus. Verifique sua conexão."),
    ("Couldn't save your session in secure storage.", "Não foi possível salvar sua sessão no armazenamento seguro."),
    ("Enter an API key.", "Digite uma chave de API."),
    ("Feather Plus returned an error ({status}).", "O Feather Plus retornou um erro ({status})."),
    ("Feather could not check for updates: {error}", "O Feather não conseguiu procurar atualizações: {error}"),
    (
        "Feather could not reach the provider. Check your connection and try again.",
        "O Feather não conseguiu acessar o provedor. Verifique sua conexão e tente novamente.",
    ),
    ("Feather could not save the credential to secure storage.", "O Feather não conseguiu salvar a credencial no armazenamento seguro."),
    (
        "Feather could not change whether it starts at login: {error}",
        "O Feather não conseguiu alterar se inicia ao ligar o computador: {error}",
    ),
    ("Feather is up to date.", "O Feather está atualizado."),
    (
        "Feather {version} is available. Install it now? Feather restarts when it finishes.",
        "O Feather {version} está disponível. Instalar agora? O Feather reinicia quando terminar.",
    ),
    ("Install", "Instalar"),
    ("Later", "Depois"),
    ("Keep your message under 5,000 characters.", "Mantenha sua mensagem com menos de 5.000 caracteres."),
    ("Open ({shortcut})", "Abrir ({shortcut})"),
    (
        "Port 1455 is in use. Close other apps signing in to ChatGPT and try again.",
        "A porta 1455 está em uso. Feche outros apps que estejam entrando no ChatGPT e tente novamente.",
    ),
    ("Quit", "Sair do Feather"),
    ("Request failed with status {status}.", "A requisição falhou com status {status}."),
    (
        "Secure credential storage is unavailable. Check that your system keyring is running.",
        "O armazenamento seguro de credenciais está indisponível. Verifique se o chaveiro do sistema está em execução.",
    ),
    ("Send Feedback", "Enviar feedback"),
    ("Send Feedback…", "Enviar feedback…"),
    ("Set a model in Settings.", "Defina um modelo nas Configurações."),
    ("Settings…", "Configurações…"),
    ("Sign in to Feather Plus in Settings.", "Entre no Feather Plus nas Configurações."),
    ("Sign in with ChatGPT in Settings.", "Entre com o ChatGPT nas Configurações."),
    ("Sign-in failed", "Falha ao entrar"),
    ("Sign-in timed out. Try again.", "O login expirou. Tente novamente."),
    ("Signed in to Feather Plus", "Você entrou no Feather Plus"),
    ("Stopped after 1 minute. Review the text before inserting it.", "Interrompido após 1 minuto. Revise o texto antes de inseri-lo."),
    ("The base URL in Settings is not valid.", "A URL base nas Configurações não é válida."),
    ("The model declined this request.", "O modelo recusou esta solicitação."),
    (
        "The model took more than 1 minute to respond. Try again or choose a faster model in Settings.",
        "O modelo levou mais de 1 minuto para responder. Tente novamente ou escolha um modelo mais rápido nas Configurações.",
    ),
    ("The update could not be installed: {error}", "Não foi possível instalar a atualização: {error}"),
    ("You can close this window and return to Feather.", "Você pode fechar esta janela e voltar ao Feather."),
    ("You've sent a lot of feedback today. Try again tomorrow.", "Você já enviou muitos feedbacks hoje. Tente de novo amanhã."),
    ("Your session expired. Sign in again.", "Sua sessão expirou. Entre novamente."),
];

#[cfg(test)]
mod tests {
    use super::TRANSLATIONS;

    #[test]
    fn every_translation_keeps_its_placeholders() {
        for (english, portuguese) in TRANSLATIONS {
            for placeholder in ["{status}", "{seconds}", "{shortcut}", "{version}", "{error}"] {
                assert_eq!(english.contains(placeholder), portuguese.contains(placeholder), "{english}");
            }
        }
    }
}
