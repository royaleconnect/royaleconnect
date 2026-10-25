-- Sample data matching the prototype (invented). Safe to run on an empty database; re-running is also safe.
-- Runs as one transaction: either everything loads or nothing does.
-- Row Level Security is switched off while loading and back on at the end, so the dashboard editor is never blocked.

begin;
alter table academic_year disable row level security;
alter table grade disable row level security;
alter table subject disable row level security;
alter table staff disable row level security;
alter table section disable row level security;
alter table teaching_assignment disable row level security;
alter table student disable row level security;
alter table family_phone disable row level security;
alter table enrolment disable row level security;
alter table fee_head disable row level security;
alter table late_fee_rule disable row level security;
alter table fee_ledger disable row level security;
alter table school_setting disable row level security;
alter table route disable row level security;
alter table route_stop disable row level security;
alter table transport_enrolment disable row level security;

-- clear any partial earlier attempt (sample ids only)
delete from transport_enrolment; delete from route_stop; delete from route;
delete from fee_ledger; delete from late_fee_rule; delete from fee_head;
delete from enrolment; delete from family_phone; delete from student;
delete from teaching_assignment; delete from section; delete from staff;
delete from subject; delete from grade; delete from school_setting; delete from academic_year;

insert into academic_year (id,label,starts_on,ends_on,is_current) values
 ('00000000-0000-0000-0000-0000000a0001','2026-27','2026-04-01','2027-03-31',true);

insert into grade (id,code,name,division,sort_order) values
 ('00000000-0000-0000-0000-0000000a1004','IV','Grade IV','primary',8),
 ('00000000-0000-0000-0000-0000000a1008','VIII','Grade VIII','middle',12),
 ('00000000-0000-0000-0000-0000000a1009','IX','Grade IX','high_senior',13);

insert into subject (id,name,short) values
 ('00000000-0000-0000-0000-0000000b1001','English','EN'),
 ('00000000-0000-0000-0000-0000000b1002','Hindi','HI'),
 ('00000000-0000-0000-0000-0000000b1003','Mathematics','MA'),
 ('00000000-0000-0000-0000-0000000b1004','Science','SC'),
 ('00000000-0000-0000-0000-0000000b1005','Social Science','SS'),
 ('00000000-0000-0000-0000-0000000b1006','Computer Science','CS');

insert into staff (id,email,full_name,display_name,roles,division) values
 ('00000000-0000-0000-0000-0000000c1001','kavitha@rcis.in','Kavitha R','Ms. Kavitha R.','{teacher,class_teacher}',null),
 ('00000000-0000-0000-0000-0000000c1002','ramesh@rcis.in','Ramesh K','Mr. Ramesh','{teacher}',null),
 ('00000000-0000-0000-0000-0000000c1003','anita@rcis.in','Anita P','Ms. Anita','{teacher}',null),
 ('00000000-0000-0000-0000-0000000c1004','meera@rcis.in','Meera S','Ms. Meera','{teacher,class_teacher}',null),
 ('00000000-0000-0000-0000-0000000c1005','rekha@rcis.in','Rekha Menon','Mrs. Rekha Menon','{coordinator}','middle'),
 ('00000000-0000-0000-0000-0000000c1006','vp@rcis.in','Anand Rao','Dr. Anand Rao','{vice_principal}',null),
 ('00000000-0000-0000-0000-0000000c1007','office@rcis.in','Noor Khudsiya','Mrs. Noor Khudsiya','{office}',null),
 ('00000000-0000-0000-0000-0000000c1008','accounts@rcis.in','Suresh N','Mr. Suresh N.','{accounts}',null),
 ('00000000-0000-0000-0000-0000000c1009','it@rcis.in','Arjun D','Mr. Arjun D.','{it_admin}',null),
 ('00000000-0000-0000-0000-0000000c1010','driver7@rcis.in','Manjunath','Mr. Manjunath','{driver}',null),
 ('00000000-0000-0000-0000-0000000c1011','cond7@rcis.in','Lakshmi','Mrs. Lakshmi','{conductor}',null);
update staff set phone='9900033333' where id='00000000-0000-0000-0000-0000000c1010';
update staff set phone='9900044444' where id='00000000-0000-0000-0000-0000000c1011';

insert into section (id,academic_year_id,grade_id,name,class_teacher_id) values
 ('00000000-0000-0000-0000-0000000d1001','00000000-0000-0000-0000-0000000a0001','00000000-0000-0000-0000-0000000a1008','B','00000000-0000-0000-0000-0000000c1001'),
 ('00000000-0000-0000-0000-0000000d1002','00000000-0000-0000-0000-0000000a0001','00000000-0000-0000-0000-0000000a1004','A','00000000-0000-0000-0000-0000000c1004');

insert into teaching_assignment (academic_year_id,section_id,subject_id,staff_id) values
 ('00000000-0000-0000-0000-0000000a0001','00000000-0000-0000-0000-0000000d1001','00000000-0000-0000-0000-0000000b1004','00000000-0000-0000-0000-0000000c1001'),
 ('00000000-0000-0000-0000-0000000a0001','00000000-0000-0000-0000-0000000d1001','00000000-0000-0000-0000-0000000b1003','00000000-0000-0000-0000-0000000c1002'),
 ('00000000-0000-0000-0000-0000000a0001','00000000-0000-0000-0000-0000000d1001','00000000-0000-0000-0000-0000000b1001','00000000-0000-0000-0000-0000000c1003');

insert into student (id,admission_no,full_name,dob,blood_group,house,father_name,mother_name,address) values
 ('00000000-0000-0000-0000-0000000e1001','LK/10/2014','Aarav Sharma','2013-04-03','B +ve','Sapphire','Mr. Rakesh Sharma','Mrs. Priya Sharma','HRBR Layout, Kalyan Nagar'),
 ('00000000-0000-0000-0000-0000000e1002','LK/22/2019','Diya Sharma','2017-11-24','A +ve','Ruby','Mr. Rakesh Sharma','Mrs. Priya Sharma','HRBR Layout, Kalyan Nagar');

insert into family_phone (student_id,phone,label,is_primary) values
 ('00000000-0000-0000-0000-0000000e1001','9845000000','Father',true),
 ('00000000-0000-0000-0000-0000000e1001','9886011111','Mother',false),
 ('00000000-0000-0000-0000-0000000e1002','9845000000','Father',true),
 ('00000000-0000-0000-0000-0000000e1002','9886011111','Mother',false);

insert into enrolment (academic_year_id,student_id,section_id,roll_no) values
 ('00000000-0000-0000-0000-0000000a0001','00000000-0000-0000-0000-0000000e1001','00000000-0000-0000-0000-0000000d1001',4),
 ('00000000-0000-0000-0000-0000000a0001','00000000-0000-0000-0000-0000000e1002','00000000-0000-0000-0000-0000000d1002',11);

insert into fee_head (id,name,kind,sort_order) values
 ('00000000-0000-0000-0000-0000000f1001','Tuition — Installment 1','tuition',1),
 ('00000000-0000-0000-0000-0000000f1002','Tuition — Installment 2','tuition',2),
 ('00000000-0000-0000-0000-0000000f1003','Tuition — Installment 3','tuition',3),
 ('00000000-0000-0000-0000-0000000f1004','Tuition — Installment 4','tuition',4),
 ('00000000-0000-0000-0000-0000000f1005','Transport — Term 1','transport',5),
 ('00000000-0000-0000-0000-0000000f1006','Transport — Term 2','transport',6),
 ('00000000-0000-0000-0000-0000000f1007','Late fee','late_fee',99);

insert into late_fee_rule (academic_year_id,grace_days,per_day,cap,effective_from) values
 ('00000000-0000-0000-0000-0000000a0001',0,100,null,'2026-04-01');

insert into fee_ledger (academic_year_id,student_id,fee_head_id,title,amount,due_on,status,paid_on) values
 ('00000000-0000-0000-0000-0000000a0001','00000000-0000-0000-0000-0000000e1001','00000000-0000-0000-0000-0000000f1001','Tuition — Installment 1',40000,'2026-04-05','paid','2026-04-02'),
 ('00000000-0000-0000-0000-0000000a0001','00000000-0000-0000-0000-0000000e1001','00000000-0000-0000-0000-0000000f1002','Tuition — Installment 2',28000,'2026-06-05','paid','2026-06-04'),
 ('00000000-0000-0000-0000-0000000a0001','00000000-0000-0000-0000-0000000e1001','00000000-0000-0000-0000-0000000f1005','Transport — Term 1',16500,'2026-06-05','paid','2026-06-04'),
 ('00000000-0000-0000-0000-0000000a0001','00000000-0000-0000-0000-0000000e1001','00000000-0000-0000-0000-0000000f1003','Tuition — Installment 3',15700,'2026-10-17','pending',null),
 ('00000000-0000-0000-0000-0000000a0001','00000000-0000-0000-0000-0000000e1001','00000000-0000-0000-0000-0000000f1006','Transport — Term 2',16500,'2026-11-05','pending',null),
 ('00000000-0000-0000-0000-0000000a0001','00000000-0000-0000-0000-0000000e1001','00000000-0000-0000-0000-0000000f1004','Tuition — Installment 4',11000,'2026-12-05','pending',null),
 ('00000000-0000-0000-0000-0000000a0001','00000000-0000-0000-0000-0000000e1002','00000000-0000-0000-0000-0000000f1001','Tuition — Installment 1',32000,'2026-04-05','paid','2026-04-02'),
 ('00000000-0000-0000-0000-0000000a0001','00000000-0000-0000-0000-0000000e1002','00000000-0000-0000-0000-0000000f1004','Tuition — Installment 4',22200,'2026-12-05','pending',null);

insert into school_setting (key,value) values
 ('quiet_hours_start','21:00'),('quiet_hours_end','06:00'),
 ('fee_reminder_days','3,0,-3,-6,-10'),
 ('urgent_senders','office,vice_principal,principal,it_admin'),
 ('tc_readonly_months','12');

insert into route (id,name,bus_reg_no,driver_staff_id,conductor_staff_id,morning_start,afternoon_start) values
 ('00000000-0000-0000-0000-0000000c7007','Route 7','KA-03-AB-1234','00000000-0000-0000-0000-0000000c1010','00000000-0000-0000-0000-0000000c1011','07:00','15:20');
insert into route_stop (route_id,seq,name,lat,lng,km_from_start) values
 ('00000000-0000-0000-0000-0000000c7007',0,'School depart',13.0244,77.6410,0),
 ('00000000-0000-0000-0000-0000000c7007',1,'Kammanahalli',13.0170,77.6360,1.4),
 ('00000000-0000-0000-0000-0000000c7007',2,'HRBR 2nd Block',13.0290,77.6420,2.6),
 ('00000000-0000-0000-0000-0000000c7007',3,'Kalyan Nagar – Stage 3',13.0255,77.6475,3.9),
 ('00000000-0000-0000-0000-0000000c7007',4,'Hennur Cross',13.0330,77.6460,5.2),
 ('00000000-0000-0000-0000-0000000c7007',5,'Banaswadi Ring Rd',13.0135,77.6530,6.8),
 ('00000000-0000-0000-0000-0000000c7007',6,'Kalyan Nagar – Stage 1',13.0215,77.6500,8.1),
 ('00000000-0000-0000-0000-0000000c7007',7,'School',13.0244,77.6410,9.4);
insert into transport_enrolment (student_id,route_id,stop_id,academic_year_id)
 select '00000000-0000-0000-0000-0000000e1001','00000000-0000-0000-0000-0000000c7007',id,'00000000-0000-0000-0000-0000000a0001' from route_stop where route_id='00000000-0000-0000-0000-0000000c7007' and seq=3;

alter table academic_year enable row level security;
alter table grade enable row level security;
alter table subject enable row level security;
alter table staff enable row level security;
alter table section enable row level security;
alter table teaching_assignment enable row level security;
alter table student enable row level security;
alter table family_phone enable row level security;
alter table enrolment enable row level security;
alter table fee_head enable row level security;
alter table late_fee_rule enable row level security;
alter table fee_ledger enable row level security;
alter table school_setting enable row level security;
alter table route enable row level security;
alter table route_stop enable row level security;
alter table transport_enrolment enable row level security;
commit;
