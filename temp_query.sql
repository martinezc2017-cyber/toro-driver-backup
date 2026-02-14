SELECT o.id, o.company_name, o.phone, u.email FROM organizers o JOIN auth.users u ON o.user_id = u.id;
