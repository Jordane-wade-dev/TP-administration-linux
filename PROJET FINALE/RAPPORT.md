# Projet : portail de suivi des tournées

Étudiante : Jordane  
Environnement : Rocky Linux 9.8, srv-core et srv-edge

## 1. Tableau de conformité

| Exigence | Vérification | Résultat |
|---|---|---|
| E1 Comptes | `id lea`, `getent passwd helios-suivi`, `chage -l lea` | Léa a l’UID 5104 et appartient uniquement à suivi (GID 5003). Sa politique de mot de passe est de 1 jour minimum, 90 jours maximum, 14 jours d’avertissement et 7 jours d’inactivité après expiration. Le compte de service a l’UID 994 et le shell nologin. [Preuve](preuves/E1-comptes.txt) |
| E2 Droits | `getfacl`, `stat` et `ls` sous le compte zabbix | Le dossier www appartient à root:suivi et a le bit setgid. La page créée par Léa est modifiable par le groupe malgré un umask de 077. Zabbix peut consulter les métadonnées de etat.json, mais ne peut pas lister www. [ACL](configs/www-acl.txt) · [Preuve](preuves/E2-droits.txt) |
| E3 Publication | Exécution du script et `python3 -m json.tool` | Le JSON est valide. J’ai obtenu le code 0 en fonctionnement normal, 2 avec le verrou déjà pris et 3 avec un compte qui ne peut pas écrire dans www. [Preuve](preuves/E3-publication.txt) |
| E4 systemd | `systemd-analyze security`, `systemctl kill`, `curl` | Score de 1,8. Après SIGKILL, le PID est passé de 12785 à 13030, le compteur de redémarrages de 0 à 1 et le portail répondait de nouveau 200. Le timer publie toutes les deux minutes. [Preuve](preuves/E4-systemd.txt) |
| E5 Sudo | `visudo -c`, `sudo -l -U lea` et essai en tant que Léa | Léa a pu consulter l’état du portail avec sudo. Le contrôle du droit de redémarrer SSH a renvoyé 1. [Règles et contrôle](preuves/E5-sudo.txt) |
| E6 Pare-feu | `firewall-cmd`, `curl` et `nc` depuis srv-edge | La zone par défaut reste drop. Le port 8080 est ouvert dans internal. Depuis srv-edge, le portail répond 200 sur le réseau métier et le test du port sur le réseau d’administration renvoie 1. [Pare-feu](preuves/E6-firewall.txt) · [Tests](preuves/E6-E7-srv-edge.txt) |
| E7 Non-régression | `sshd -T`, journal SSH et liste des démarrages | SSH reste sur 2242, avec les connexions root et par mot de passe désactivées. Le journal confirme le refus de Léa par AllowGroups. Le timer de surveillance est actif et le journal du démarrage précédent est disponible. [Preuve](preuves/E7-securite.txt) |
| E8 Supervision | `zabbix_get` sur helios.suivi.http et helios.suivi.age | L’agent et la collecte sysstat sont actifs. Les sondes ont renvoyé 200 et 86 secondes. [Preuve](preuves/E8-zabbix.txt) |
| E9 Sauvegarde | `sha256sum -c`, `tar --acls`, `getfacl`, `systemctl list-timers` | Empreinte OK, ACL identiques et restauration de la page réussie. La sauvegarde est planifiée à 03 h 15. [Preuve](preuves/E9-restauration.txt) |

## 2. Justifications

**Durcissement.** Le portail tourne sous helios-suivi avec ProtectSystem=strict, sans capacités supplémentaires et avec des limites de 128 Mio et 50 % de CPU. Le service de publication a une exception d’écriture pour www. Le score du portail est de 1,8 et les deux URL testées répondent 200.

**Accès Zabbix.** Le droit --x permet de traverser www pour faire un stat sur un fichier dont on connaît le nom. Avec r-x, le compte pourrait aussi lister le dossier. J’ai vérifié qu’avec --x, stat fonctionne et ls est refusé.

**Règle sudo.** Un joker dans les arguments de journalctl pourrait permettre d’ajouter des options comme --vacuum-time, qui peut supprimer des journaux archivés. J’ai fixé l’unité, le nombre de lignes et l’option --no-pager dans chaque commande autorisée.

## 3. Test de restauration

J’ai vérifié l’empreinte avec `sha256sum -c`, puis extrait l’archive dans un dossier de test avec `tar --acls --selinux -xzf`. J’ai comparé les ACL de www avec `getfacl` et `diff`. Elles étaient identiques.

J’ai ensuite supprimé index.html et extrait uniquement ce fichier à son emplacement d’origine. J’ai vérifié le contenu avec `cmp`, les ACL avec `diff` et l’affichage avec `curl`. Le portail a de nouveau servi la page.

La suppression et la restauration ont pris 180 154 ms, soit environ 3 minutes, attente de la confirmation comprise. Les [sorties du test](preuves/E9-restauration.txt) montrent le résultat.

## 4. Mesure sous charge

Les 2 000 requêtes ont réussi. Le CPU cumulé du portail est passé de 1,562 à 4,455 secondes et la mémoire de 10 223 616 à 10 268 672 octets. Voir le [relevé sar](preuves/charge-sar.txt) et les [compteurs du service](preuves/charge-portail.txt).

Le quota CPU de 50 % n’a pas freiné le portail pendant ce test. Le compteur nr_throttled est resté à 4 et throttled_usec à 157 405.

## 5. Limites connues

Les requêtes du test de charge ont été envoyées une par une. Avec plus de temps, je testerais des connexions simultanées et je vérifierais la rétention en créant plus de sept sauvegardes.
